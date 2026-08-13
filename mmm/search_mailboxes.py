#!/usr/bin/python3

"""
Alfred Mail mailbox Script Filter helper.

This module:

1. Runs selected_account.applescript to determine which Mail account owns the
   currently selected messages.
2. Stops silently if no usable account is returned. The AppleScript itself
   handles beeping for an empty or mixed-account selection.
3. Finds the corresponding account directory beneath ~/Library/Mail.
4. Enumerates that account's .mbox directories.
5. Fuzzy-filters mailbox paths at word boundaries.
6. Returns Alfred Script Filter JSON.

The module may be imported from another Python script or executed directly.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path

WORKFLOW_DIR = Path(__file__).resolve().parent
ACCOUNT_SCRIPT = WORKFLOW_DIR / "get_selected_account.applescript"


def parse_args(argv=None):
    """
    Parse the optional fuzzy-search query.

    The account ID is no longer supplied by Alfred. It is obtained directly
    from Mail by selected_account.applescript.

    Examples:

        python3 mailboxes.py
        python3 mailboxes.py "proj cli"
    """
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "query",
        nargs="?",
        default="",
        help="Optional mailbox search query",
    )

    args = parser.parse_args(argv)
    args.query = args.query.strip()

    return args


def get_selected_account_id() -> str | None:
    """
    Run the workflow's AppleScript and return the selected Mail account ID.

    The AppleScript returns an empty string when:

      - there are no selected messages, or
      - the selected messages belong to different accounts.

    In those cases it also performs the system beep, so Python simply returns
    None and produces no Alfred results.
    """
    result = subprocess.run(
        [
            "/usr/bin/osascript",
            str(ACCOUNT_SCRIPT),
        ],
        capture_output=True,
        text=True,
        check=False,
    )

    account_id = result.stdout.strip()

    if result.returncode != 0:
        raise RuntimeError(
            result.stderr.strip() or "Unable to determine selected Mail account"
        )

    return account_id or None


def get_mail_root() -> Path:
    """
    Find the newest versioned Apple Mail data directory.

    Mail stores local data under directories such as:

        ~/Library/Mail/V10
        ~/Library/Mail/V11

    Rather than hard-coding a macOS-specific version, select the highest
    numeric V* directory available.
    """
    root = Path.home() / "Library" / "Mail"

    versions = []

    for path in root.glob("V*"):
        if not path.is_dir():
            continue

        match = re.fullmatch(r"V(\d+)", path.name)

        if match:
            versions.append((int(match.group(1)), path))

    if not versions:
        raise RuntimeError("Could not find ~/Library/Mail/V*")

    return max(versions, key=lambda item: item[0])[1]


def find_account_dir(mail_root: Path, account_id: str) -> Path:
    """
    Locate the local Mail directory corresponding to an account ID.

    Check direct children first because that is considerably cheaper than a
    recursive traversal. A recursive fallback makes the code more tolerant of
    differences in Mail's internal directory layout.
    """
    wanted = account_id.strip().casefold()

    for path in mail_root.iterdir():
        if path.is_dir() and path.name.casefold() == wanted:
            return path

    for path in mail_root.rglob("*"):
        if path.is_dir() and path.name.casefold() == wanted:
            return path

    raise RuntimeError(f"Could not locate Mail directory for account {account_id!r}")


def mailbox_parts(account_dir: Path, mailbox: Path) -> list[str]:
    """
    Extract the logical mailbox hierarchy from a filesystem path.

    Mail may insert internal implementation directories between nested
    mailboxes. Only path components ending in .mbox are considered mailbox
    names.

    For example, a filesystem path containing:

        Projects.mbox/.../Clients.mbox/.../Acme.mbox

    becomes:

        ["Projects", "Clients", "Acme"]
    """
    relative = mailbox.relative_to(account_dir)

    return [
        component[:-5] for component in relative.parts if component.endswith(".mbox")
    ]


def get_mailboxes(account_dir: Path) -> list[dict]:
    """
    Enumerate all mailboxes below an account directory.

    Each mailbox record contains:

        name:         leaf mailbox name
        logical_path: complete logical mailbox path
        directory:    underlying .mbox directory

    For example:

        Acme
        Projects / Clients / Acme
    """
    mailboxes = []

    for path in account_dir.rglob("*.mbox"):
        if not path.is_dir():
            continue

        parts = mailbox_parts(account_dir, path)

        if not parts:
            continue

        mailboxes.append(
            {
                "name": parts[-1],
                "logical_path": " / ".join(parts),
                "directory": path,
            }
        )

    return mailboxes


def words(value: str) -> list[str]:
    """
    Convert text into normalized words for fuzzy matching.
    """
    return re.findall(r"\w+", value.casefold())


def fuzzy_word_match(needle: str, word: str) -> bool:
    """
    Fuzzy-match a query token against a candidate word.

    Matching is anchored to the candidate's word boundary: the first
    characters must match. Subsequent characters need only occur in order.

    Examples:

        "proj" -> "Projects"   True
        "pj"   -> "Projects"   True
        "prj"  -> "Projects"   True
        "roj"  -> "Projects"   False
    """
    if not needle:
        return True

    if not word or needle[0] != word[0]:
        return False

    position = 0

    for char in needle:
        position = word.find(char, position)

        if position == -1:
            return False

        position += 1

    return True


def fuzzy_path_match(query: str, candidate: str) -> bool:
    """
    Fuzzy-match a query against mailbox words in order.

    Each query token must match from the beginning of a candidate word. Words
    between matches may be skipped.

    Examples:

        "pr cl"
            matches "Projects / Current Clients"

        "pj cc"
            matches "Projects / Current Clients"

        "proj ac"
            matches "Projects / Clients / Acme"

        "roj"
            does not match "Projects"
    """
    needles = words(query.strip())

    if not needles:
        return True

    candidate_words = words(candidate)
    candidate_index = 0

    for needle in needles:
        found = False

        while candidate_index < len(candidate_words):
            if fuzzy_word_match(
                needle,
                candidate_words[candidate_index],
            ):
                found = True
                candidate_index += 1
                break

            candidate_index += 1

        if not found:
            return False

    return True


def build_items(
    account_id: str,
    mailboxes: list[dict],
    query: str = "",
) -> list[dict]:
    """
    Filter and convert mailbox records to Alfred Script Filter items.
    """
    filtered = [
        mailbox
        for mailbox in mailboxes
        if fuzzy_path_match(query, mailbox["logical_path"])
    ]

    # Leaf name is the primary sort key because it is also Alfred's result
    # title. The full path resolves ties when identical folder names exist at
    # different points in the hierarchy.
    filtered.sort(
        key=lambda mailbox: (
            mailbox["name"].casefold(),
            mailbox["logical_path"].casefold(),
        )
    )

    return [
        {
            "uid": str(mailbox["directory"]),
            "title": mailbox["name"],
            "subtitle": mailbox["logical_path"],
            "arg": mailbox["logical_path"],
            "variables": {
                "account_id": account_id,
                "mailbox_path": str(mailbox["directory"]),
                "mailbox_name": mailbox["name"],
                "mailbox_display_path": mailbox["logical_path"],
            },
        }
        for mailbox in filtered
    ]


def get_results(query: str = "") -> dict:
    """
    Main reusable API for callers that import this module.

    Returns a dictionary already shaped for Alfred Script Filter JSON.
    """
    account_id = get_selected_account_id()

    # The AppleScript has already beeped. Returning no items prevents Alfred
    # from presenting folders from an invalid or ambiguous selection.
    if not account_id:
        return {"items": []}

    mail_root = get_mail_root()
    account_dir = find_account_dir(mail_root, account_id)
    mailboxes = get_mailboxes(account_dir)

    return {
        "items": build_items(
            account_id=account_id,
            mailboxes=mailboxes,
            query=query.strip(),
        )
    }


def main(argv=None):
    """
    Command-line entry point.

    Errors are represented as invalid Alfred results so they remain visible in
    the debugger/UI instead of producing malformed Script Filter output.
    """
    args = parse_args(argv)

    try:
        results = get_results(args.query)

    except Exception as exc:
        results = {
            "items": [
                {
                    "title": "Unable to read Mail folders",
                    "subtitle": str(exc),
                    "valid": False,
                }
            ]
        }

    print(json.dumps(results))


if __name__ == "__main__":
    main()
