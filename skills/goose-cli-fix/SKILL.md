---
name: goose-cli-fix
description: Fix the Goose CLI "Failed to parse projects.json file" warning by repairing malformed JSON in the project tracker file
metadata:
  tags: [goose, cli, fix, json]
---

# Fix Goose CLI projects.json Parse Error

Fix the warning `Failed to update project tracker with instruction: Failed to parse projects.json file` that can occur after updating Goose CLI, caused by malformed JSON in the project tracker file.

## Steps

1. **Locate the projects.json file**
   The project tracker file is at:
   ```
   ~/.local/share/goose/projects.json
   ```
   Verify it exists:
   ```
   ls -la ~/.local/share/goose/projects.json
   ```

2. **Validate the JSON**
   Check whether the file contains valid JSON:
   ```
   python3 -m json.tool ~/.local/share/goose/projects.json > /dev/null
   ```
   If this reports an error, the file is malformed and needs repair.

3. **Inspect the file for common issues**
   Read the file and look for:
   - Extra trailing closing braces `}` at the end of the file (most common cause)
   - Duplicate keys or other JSON syntax errors
   - Truncated or corrupted content

4. **Repair the JSON**
   Fix the identified issues. The most common problem is extra `}}` or `}` appended to the end of the file after an update. Remove the extra braces so the file ends with a single closing `}` matching the opening `{` of the root object. The correct structure is:
   ```json
   {
     "projects": {
       "/path/to/project": {
         "path": "/path/to/project",
         "last_accessed": "...",
         "last_instruction": "...",
         "last_session_id": "..."
       }
     }
   }
   ```

5. **Validate the fix**
   Confirm the repaired file is valid JSON:
   ```
   python3 -m json.tool ~/.local/share/goose/projects.json > /dev/null
   ```

## Notes

- If the file is too corrupted to repair, it is safe to replace it with an empty project tracker: `{"projects": {}}`. Goose will repopulate it as you use different project directories.
- Do **not** leave backup files behind after the fix — clean up any `.bak` copies.

## Verification

- [ ] `python3 -m json.tool ~/.local/share/goose/projects.json` exits with no errors
- [ ] The Goose CLI warning no longer appears on next session start

## Changelog

| Updated | Change |
|---------|--------|
| 2026-06-26 09:20 | v1.0 — Initial skill |
