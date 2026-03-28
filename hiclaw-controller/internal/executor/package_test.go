package executor

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestWriteInlineConfigs_AllFields_OpenClaw(t *testing.T) {
	dir := t.TempDir()

	err := WriteInlineConfigs(dir, "openclaw", "identity content", "soul content", "agents content")
	if err != nil {
		t.Fatalf("WriteInlineConfigs failed: %v", err)
	}

	assertFileContent(t, filepath.Join(dir, "IDENTITY.md"), "identity content")
	assertFileContent(t, filepath.Join(dir, "SOUL.md"), "soul content")
	assertFileContains(t, filepath.Join(dir, "AGENTS.md"), "agents content")
}

func TestWriteInlineConfigs_AllFields_CoPaw(t *testing.T) {
	dir := t.TempDir()

	err := WriteInlineConfigs(dir, "copaw", "identity content", "soul content", "agents content")
	if err != nil {
		t.Fatalf("WriteInlineConfigs failed: %v", err)
	}

	// CoPaw: no IDENTITY.md
	if _, err := os.Stat(filepath.Join(dir, "IDENTITY.md")); err == nil {
		t.Error("IDENTITY.md should not exist for copaw runtime")
	}

	// SOUL.md should contain identity prepended to soul
	soulData, err := os.ReadFile(filepath.Join(dir, "SOUL.md"))
	if err != nil {
		t.Fatalf("failed to read SOUL.md: %v", err)
	}
	soul := string(soulData)
	if !strings.HasPrefix(soul, "identity content") {
		t.Errorf("SOUL.md should start with identity content, got: %s", soul[:min(len(soul), 50)])
	}
	if !strings.Contains(soul, "soul content") {
		t.Error("SOUL.md should contain soul content")
	}

	assertFileContains(t, filepath.Join(dir, "AGENTS.md"), "agents content")
}

func TestWriteInlineConfigs_SoulOnly(t *testing.T) {
	dir := t.TempDir()

	err := WriteInlineConfigs(dir, "", "", "soul only", "")
	if err != nil {
		t.Fatalf("WriteInlineConfigs failed: %v", err)
	}

	assertFileContent(t, filepath.Join(dir, "SOUL.md"), "soul only")

	if _, err := os.Stat(filepath.Join(dir, "IDENTITY.md")); err == nil {
		t.Error("IDENTITY.md should not exist when identity is empty")
	}
	if _, err := os.Stat(filepath.Join(dir, "AGENTS.md")); err == nil {
		t.Error("AGENTS.md should not exist when agents is empty")
	}
}

func TestWriteInlineConfigs_OverridesExisting(t *testing.T) {
	dir := t.TempDir()

	// Pre-create files
	os.WriteFile(filepath.Join(dir, "SOUL.md"), []byte("old soul"), 0644)
	os.WriteFile(filepath.Join(dir, "AGENTS.md"), []byte("old agents"), 0644)

	err := WriteInlineConfigs(dir, "", "", "new soul", "new agents")
	if err != nil {
		t.Fatalf("WriteInlineConfigs failed: %v", err)
	}

	assertFileContent(t, filepath.Join(dir, "SOUL.md"), "new soul")
	assertFileContains(t, filepath.Join(dir, "AGENTS.md"), "new agents")

	// Verify old content is gone
	data, _ := os.ReadFile(filepath.Join(dir, "SOUL.md"))
	if strings.Contains(string(data), "old soul") {
		t.Error("SOUL.md should not contain old content")
	}
}

func TestWriteInlineConfigs_AgentsWrappedWithMarkers(t *testing.T) {
	dir := t.TempDir()

	err := WriteInlineConfigs(dir, "", "", "", "custom agents rules")
	if err != nil {
		t.Fatalf("WriteInlineConfigs failed: %v", err)
	}

	data, err := os.ReadFile(filepath.Join(dir, "AGENTS.md"))
	if err != nil {
		t.Fatalf("failed to read AGENTS.md: %v", err)
	}
	content := string(data)
	if !strings.Contains(content, "<!-- hiclaw-builtin-start -->") {
		t.Error("AGENTS.md should contain builtin-start marker")
	}
	if !strings.Contains(content, "<!-- hiclaw-builtin-end -->") {
		t.Error("AGENTS.md should contain builtin-end marker")
	}
	if !strings.Contains(content, "custom agents rules") {
		t.Error("AGENTS.md should contain custom content")
	}
}

func TestWriteInlineConfigs_CoPawMergesIdentityIntoSoul(t *testing.T) {
	dir := t.TempDir()

	err := WriteInlineConfigs(dir, "copaw", "# Identity\nName: Alice", "# Role\nDevOps engineer", "")
	if err != nil {
		t.Fatalf("WriteInlineConfigs failed: %v", err)
	}

	data, err := os.ReadFile(filepath.Join(dir, "SOUL.md"))
	if err != nil {
		t.Fatalf("failed to read SOUL.md: %v", err)
	}
	content := string(data)

	// Identity should come before soul
	idxIdentity := strings.Index(content, "# Identity")
	idxRole := strings.Index(content, "# Role")
	if idxIdentity < 0 || idxRole < 0 {
		t.Fatalf("expected both identity and role in SOUL.md, got: %s", content)
	}
	if idxIdentity >= idxRole {
		t.Error("identity should be prepended before soul content")
	}
}

func TestWriteInlineConfigs_CoPawIdentityOnly(t *testing.T) {
	dir := t.TempDir()

	err := WriteInlineConfigs(dir, "copaw", "identity only", "", "")
	if err != nil {
		t.Fatalf("WriteInlineConfigs failed: %v", err)
	}

	assertFileContent(t, filepath.Join(dir, "SOUL.md"), "identity only")
}

func TestWriteInlineConfigs_CreatesDir(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "nested", "agent")

	err := WriteInlineConfigs(dir, "", "", "soul", "")
	if err != nil {
		t.Fatalf("WriteInlineConfigs failed: %v", err)
	}

	assertFileContent(t, filepath.Join(dir, "SOUL.md"), "soul")
}

func TestWriteInlineConfigs_EmptyFields(t *testing.T) {
	dir := t.TempDir()

	err := WriteInlineConfigs(dir, "", "", "", "")
	if err != nil {
		t.Fatalf("WriteInlineConfigs failed: %v", err)
	}

	entries, _ := os.ReadDir(dir)
	if len(entries) != 0 {
		t.Errorf("expected no files written when all fields empty, got %d", len(entries))
	}
}

// --- helpers ---

func assertFileContent(t *testing.T, path, expected string) {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("failed to read %s: %v", filepath.Base(path), err)
	}
	content := strings.TrimSpace(string(data))
	if content != expected {
		t.Errorf("%s: expected %q, got %q", filepath.Base(path), expected, content)
	}
}

func assertFileContains(t *testing.T, path, substr string) {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("failed to read %s: %v", filepath.Base(path), err)
	}
	if !strings.Contains(string(data), substr) {
		t.Errorf("%s should contain %q", filepath.Base(path), substr)
	}
}
