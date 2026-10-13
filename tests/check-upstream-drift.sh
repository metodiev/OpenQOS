#!/bin/bash
#
# Report where OpenQOS's own copy of a Fedora description file has drifted from
# the upstream revision we pin.
#
#   tests/check-upstream-drift.sh
#
# Run inside the development VM, after scripts/fetch-upstream-descriptions.sh.
#
# Why this exists
# ---------------
# Most of the time OpenQOS *includes* Fedora's descriptions rather than copying
# them, so an upstream fix arrives by changing the pinned commit and nothing else.
# Where we copy instead — kiwi/openqos/desktop-common.xml, which drops
# `mediawriter` — upstream additions stop reaching us, silently. That silence is
# the cost of owning a file, and this is what makes it audible: the difference is
# printed on every run, and the script fails when the difference is anything other
# than the one we intended.
#
# The comparison is over entry *sets*, not text. Upstream reorders and reformats
# these files freely, and a textual diff would fail on whitespace while saying
# nothing about what actually changed.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

upstream="${repo_root}/kiwi/upstream/components/desktops/common.xml"
ours="${repo_root}/kiwi/openqos/desktop-common.xml"

for file in "${upstream}" "${ours}"; do
	if [[ ! -f "${file}" ]]; then
		echo "error: ${file} not found." >&2
		echo "       Run scripts/fetch-upstream-descriptions.sh first." >&2
		exit 1
	fi
done

# The one delta OpenQOS intends. Written out rather than derived, so a second
# divergence cannot hide behind the first.
expected_removed="package mediawriter"
expected_added="ignore mediawriter"

# Entries that decide what lands in the image. Comments are removed first: this
# file documents the upstream delta by quoting the very elements being compared,
# and a line-based extraction would otherwise read the documentation as content.
entries() {
	awk '/<!--/,/-->/ { next } { print }' "$1" |
		sed -n -E 's/.*<(package|ignore|namedCollection) name="([^"]+)".*/\1 \2/p' |
		sort -u
}

# Same reasoning, and the returned text keeps the elements on their own lines so
# that diff can report them.
profile_elements() {
	awk '/<!--/,/-->/ { next } { print }' "$1" |
		grep -oE '<(profile|requires) [^>]*>' |
		sed -E 's/ description="[^"]*"//'
}

echo "Comparing kiwi/openqos/desktop-common.xml against upstream:"
echo "  ${upstream#"${repo_root}/"}"
echo

upstream_entries="$(entries "${upstream}")"
ours_entries="$(entries "${ours}")"

removed="$(comm -23 <(printf '%s\n' "${upstream_entries}") <(printf '%s\n' "${ours_entries}"))"
added="$(comm -13 <(printf '%s\n' "${upstream_entries}") <(printf '%s\n' "${ours_entries}"))"

printf '%s\n' "  upstream entries : $(printf '%s\n' "${upstream_entries}" | wc -l)"
printf '%s\n' "  OpenQOS entries  : $(printf '%s\n' "${ours_entries}" | wc -l)"
echo

status=0

if [[ "${removed}" == "${expected_removed}" && "${added}" == "${expected_added}" ]]; then
	echo "  intended delta   : ${expected_removed} replaced by ${expected_added}"
else
	echo "  DRIFT — the difference is not the one OpenQOS intends:" >&2
	diff <(printf '%s\n' "${upstream_entries}") <(printf '%s\n' "${ours_entries}") >&2 || true
	status=1
fi

echo
echo "Profile requirements (these must match upstream exactly):"
if diff <(profile_elements "${upstream}") <(profile_elements "${ours}"); then
	echo "  identical"
else
	echo "  DRIFT — a profile requirement differs from upstream." >&2
	status=1
fi

echo
if [[ "${status}" -ne 0 ]]; then
	echo "Result: drift. Either an upstream change needs taking deliberately, or the" >&2
	echo "        difference above was introduced by accident." >&2
	exit 1
fi

echo "Result: only the documented delta. Upstream has not added anything we are missing."

# --- the GRUB template --------------------------------------------------------
#
# kiwi/templates/grub-arm.cfg.iso-template shadows upstream's file of the same
# name because that is the name upstream's type asks for. The claim made in that
# file is that its *body* is byte-identical to upstream's except for the menu
# class, and a claim like that is worth checking rather than asserting. Our own
# header comment is stripped first, so it cannot mask a real difference.

upstream_grub="${repo_root}/kiwi/upstream/grub-arm.cfg.iso-template"
our_grub="${repo_root}/kiwi/templates/grub-arm.cfg.iso-template"

if [[ ! -f "${our_grub}" ]]; then
	echo
	echo "GRUB template: not present, nothing to check."
	exit 0
fi

echo
echo "Comparing kiwi/templates/grub-arm.cfg.iso-template body against upstream:"

# Our header ends at the first blank line after the trailing marker comment.
# Everything after that blank line is upstream's content.
body_start="$(awk 'BEGIN { seen = 0 } /^$/ { if (seen) { print NR + 1; exit } } { if ($0 ~ /^#/) seen = 1; else seen = 0 }' "${our_grub}")"
if [[ -z "${body_start}" ]]; then
	echo "  error: cannot find where the header ends in ${our_grub}" >&2
	exit 1
fi

unexpected="$(diff "${upstream_grub}" <(tail -n "+${body_start}" "${our_grub}") | grep '^[<>]' | grep -v -- '--class' || true)"
if [[ -n "${unexpected}" ]]; then
	echo "  DRIFT — the body differs from upstream by more than the menu class:" >&2
	printf '    %s\n' "${unexpected}" >&2
	exit 1
fi

# Count upstream-side lines only: diff reports each change twice, once as "<" and
# once as ">", and the number of changed lines is the "<" side.
substitutions="$(diff "${upstream_grub}" <(tail -n "+${body_start}" "${our_grub}") | grep -c '^<.*--class' || true)"
echo "  body identical to upstream except ${substitutions} lines, all of them the menu class"
echo
echo "Result: the GRUB template differs only in the way it says it does."
