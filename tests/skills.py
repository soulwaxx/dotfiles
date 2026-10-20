#!/usr/bin/env python3
"""Check the shared skill tree and the always-on instruction budget."""

from pathlib import Path
import re
import sys

# Keep shared always-on instructions within the prompt budget.
ALWAYS_ON_BUDGET = 8_000
MANUAL_DESCRIPTION_MAX = 250
# Phrases that ask the model to fire a skill on its own. They are useless on a
# user-invoked skill, whose description is a human-facing summary.
AUTONOMOUS_TRIGGERS = ("proactively", "always use", "also activates", "consult before", "even without")
MODEL_TRIGGERS = ("use when", "invoke")
LINK = re.compile(r"\]\(([^)\s]+)\)")


def frontmatter(path):
    text = path.read_text()
    assert text.startswith("---\n"), path
    header = text.split("---", 2)[1]
    fields = {}
    for line in header.splitlines():
        if line.strip():
            key, value = line.split(":", 1)
            fields[key.strip()] = value.strip().strip('"')
    return fields


def prose_lines(path):
    fenced = False
    for line in path.read_text().splitlines():
        if line.lstrip().startswith("```"):
            fenced = not fenced
            continue
        if not fenced:
            yield re.sub(r"`[^`]*`", "", line)


def check_skill(directory):
    skill = directory / "SKILL.md"
    assert skill.is_file(), f"{directory.name}: missing SKILL.md"
    fields = frontmatter(skill)
    assert fields.get("name") == directory.name, f"{directory.name}: name is {fields.get('name')!r}"
    description = fields.get("description", "")
    assert description, f"{directory.name}: empty description"
    lowered = description.lower()
    if fields.get("disable-model-invocation") == "true":
        assert len(description) <= MANUAL_DESCRIPTION_MAX, f"{directory.name}: manual description too long"
        for phrase in AUTONOMOUS_TRIGGERS:
            assert phrase not in lowered, f"{directory.name}: manual skill uses trigger phrase {phrase!r}"
    else:
        assert any(p in lowered for p in MODEL_TRIGGERS), f"{directory.name}: model-invoked skill lacks trigger phrasing"

    for doc in sorted(directory.rglob("*.md")):
        for line in prose_lines(doc):
            for target in LINK.findall(line):
                if re.match(r"[a-z]+:|#|/", target):
                    continue
                resolved = doc.parent / target.split("#", 1)[0]
                assert resolved.exists(), f"{doc.relative_to(directory.parent)}: broken link {target}"


def main():
    skills = Path(sys.argv[1])
    always_on = [Path(arg) for arg in sys.argv[2:]]
    directories = sorted(p for p in skills.iterdir() if p.is_dir())
    assert directories, skills
    for directory in directories:
        check_skill(directory)

    size = sum(len(path.read_text()) for path in always_on)
    assert size <= ALWAYS_ON_BUDGET, f"always-on text is {size} chars, budget {ALWAYS_ON_BUDGET}"


if __name__ == "__main__":
    main()
