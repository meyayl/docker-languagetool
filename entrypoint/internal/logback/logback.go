// Package logback patches the LanguageTool logback XML configuration file
// to set the desired log level before the server starts.
package logback

import (
	"fmt"
	"io"
	"os"

	"github.com/beevik/etree"
)

// PatchLogLevel copies src to dst then updates the @level attribute on
// /configuration/logger[@name='org.languagetool'], replicating:
//
//	xmlstarlet edit --inplace \
//	  --update "/configuration/logger[@name='org.languagetool']/@level" \
//	  --value "$LOG_LEVEL" /tmp/logback.xml
func PatchLogLevel(src, dst, level string) error {
	if err := copyFile(src, dst); err != nil {
		return fmt.Errorf("copy %s → %s: %w", src, dst, err)
	}

	doc := etree.NewDocument()
	if err := doc.ReadFromFile(dst); err != nil {
		return fmt.Errorf("parse %s: %w", dst, err)
	}

	root := doc.Root()
	if root == nil {
		return fmt.Errorf("no root element in %s", dst)
	}

	for _, child := range root.ChildElements() {
		if child.Tag != "logger" {
			continue
		}
		if child.SelectAttrValue("name", "") == "org.languagetool" {
			child.CreateAttr("level", level)
			if err := doc.WriteToFile(dst); err != nil {
				return fmt.Errorf("write %s: %w", dst, err)
			}
			return nil
		}
	}
	return fmt.Errorf("logger[@name='org.languagetool'] not found in %s", dst)
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}

	if _, err = io.Copy(out, in); err != nil {
		out.Close()
		os.Remove(dst)
		return err
	}
	return out.Close()
}
