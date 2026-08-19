#!/usr/bin/env python3
"""regen-skill-index.py — Regenerate skills/index.md from SKILL.md metadata.

Usage: python3 regen-skill-index.py <skills_root>

Scans every immediate subdirectory of <skills_root> for SKILL.md files,
extracts frontmatter metadata (name, description, tags), validates
name-directory consistency, and generates an index.md sorted by
reverse chronological order (newest first).

Exit codes:
  0 = all checks passed
  1 = warnings found (still generates index)
"""

import os
import re
import sys
import datetime


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 regen-skill-index.py <skills_root>", file=sys.stderr)
        sys.exit(2)

    skills_root = sys.argv[1]
    if not os.path.isdir(skills_root):
        print(f"ERROR: not a directory: {skills_root}", file=sys.stderr)
        sys.exit(2)

    entries = []
    warnings = []

    for d in sorted(os.listdir(skills_root)):
        skill_dir = os.path.join(skills_root, d)
        skill_file = os.path.join(skill_dir, 'SKILL.md')
        if not os.path.isdir(skill_dir) or not os.path.isfile(skill_file):
            continue

        with open(skill_file, 'r') as f:
            content = f.read()

        name = d
        description = ''
        tags = ''

        if content.startswith('---'):
            parts = content.split('---', 2)
            if len(parts) >= 3:
                fm = parts[1]

                # Name
                m = re.search(r'^name:\s*["\']?(.+?)["\']?\s*$', fm, re.M)
                if m:
                    fname = m.group(1).strip()
                    if fname != d:
                        warnings.append(f'WARNING: name mismatch — dir=[{d}] name=[{fname}]')
                    name = fname
                else:
                    warnings.append(f'WARNING: missing name field — dir=[{d}]')

                # Description (multi-line scalar support)
                m = re.search(r'^description:\s*([>|][-]?)\s*$', fm, re.M)
                if m:
                    start = m.end()
                    lines = []
                    for line in fm[start:].split('\n'):
                        if line and (line[0] == ' ' or line[0] == '\t'):
                            lines.append(line.strip())
                        elif line.strip() == '':
                            continue
                        else:
                            break
                    description = ' '.join(lines)
                else:
                    m = re.search(r'^description:\s*["\']?(.+?)["\']?\s*$', fm, re.M)
                    if m:
                        description = m.group(1).strip()

                # Tags
                m = re.search(r'tags:\s*\[([^\]]+)\]', fm)
                if m:
                    tags = ', '.join(t.strip().strip('"\'') for t in m.group(1).split(','))

                # Version check
                meta_version = None
                m = re.search(r'^\s*version:\s*["\']?([^"\']*)["\'\s]', fm, re.M)
                if m:
                    meta_version = m.group(1).strip()
                else:
                    warnings.append(f'WARNING: missing metadata.version — dir=[{d}]')

                # Version-CHANGELOG alignment check
                changelog_path = os.path.join(skill_dir, 'CHANGELOG.md')
                if meta_version and os.path.isfile(changelog_path):
                    with open(changelog_path, 'r') as cf:
                        for cl_line in cf:
                            vm = re.search(r'v(\d+\.\d+(?:\.\d+)?)', cl_line)
                            if vm:
                                cl_version = vm.group(1)
                                # Normalize: strip trailing .0 for comparison
                                # so "1.0.0" matches "1.0" and "4.0.0" matches "4.0"
                                def norm_ver(v):
                                    parts = v.split('.')
                                    while len(parts) > 2 and parts[-1] == '0':
                                        parts.pop()
                                    return '.'.join(parts)
                                if norm_ver(cl_version) != norm_ver(meta_version):
                                    warnings.append(
                                        f'WARNING: version mismatch — dir=[{d}] '
                                        f'metadata.version=[{meta_version}] '
                                        f'CHANGELOG latest=[{cl_version}]')
                                break

                # Legacy signals check
                if re.search(r'^\s*signals:', fm, re.M):
                    warnings.append(f'WARNING: legacy metadata.signals found — dir=[{d}]')
        else:
            for line in content.split('\n'):
                line = line.strip()
                if not line or line.startswith('#') or line.startswith('|') or \
                   line.startswith('---') or line.startswith('>'):
                    continue
                description = line
                break

        # Use newest mtime across all files in the skill directory
        skill_dir = os.path.dirname(skill_file)
        mtime = max(
            os.stat(os.path.join(root, f)).st_mtime
            for root, _, files in os.walk(skill_dir)
            for f in files
        )
        ts = datetime.datetime.fromtimestamp(mtime).strftime('%Y-%m-%d %H:%M')
        entries.append((ts, d, name, tags, description))

    # Sort newest first
    entries.sort(key=lambda e: e[0], reverse=True)

    # Generate index.md
    lines = [
        '# Skills Index', '',
        f'> {len(entries)} skills | Sorted by reverse chronological order (newest first).', '',
        '| Skill | Tags | Description | Updated |',
        '|-------|------|-------------|---------|',
    ]
    for ts, d, name, tags, desc in entries:
        lines.append(f'| [{name}](./{d}/SKILL.md) | {tags} | {desc} | {ts} |')

    index_path = os.path.join(skills_root, 'index.md')
    with open(index_path, 'w') as f:
        f.write('\n'.join(lines) + '\n')

    print(f'  ✅ Indexed {len(entries)} skills → {index_path}')
    for w in warnings:
        print(f'  ⚠️  {w}')

    sys.exit(1 if warnings else 0)


if __name__ == '__main__':
    main()
