#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
publication_root=${PERFORMANCE_PUBLICATION_ROOT:-$backend_dir/build/agda29}
staging_result=${PERFORMANCE_STAGING_RESULT:?PERFORMANCE_STAGING_RESULT is required}
final_result=${PERFORMANCE_FINAL_RESULT:-$publication_root/formal-transport-performance}
expected_result=${PERFORMANCE_TERMINAL_RESULT:?PERFORMANCE_TERMINAL_RESULT is required}

case "$expected_result" in
  ENGINEERING-PERFORMANCE-PASS|ENGINEERING-PERFORMANCE-FAIL) ;;
  *) echo "Invalid performance terminal result" >&2; exit 2 ;;
esac

[ -d "$publication_root" ] && [ -d "$staging_result" ] || {
  echo "Performance publication root or staging result is missing" >&2
  exit 2
}
publication_root=$(CDPATH= cd -- "$publication_root" && pwd -P)
staging_parent=$(CDPATH= cd -- "$(dirname -- "$staging_result")" && pwd -P)
final_parent=$(CDPATH= cd -- "$(dirname -- "$final_result")" && pwd -P)
staging_name=$(basename "$staging_result")
final_name=$(basename "$final_result")
case "$final_name" in
  formal-transport-performance|formal-transport-performance-release) ;;
  *) echo "Invalid performance final directory name" >&2; exit 2 ;;
esac
case "$staging_name" in
  "$final_name".pending.*) ;;
  *) echo "Invalid performance staging directory name" >&2; exit 2 ;;
esac
if [ "$staging_parent" != "$publication_root" ] || \
   [ "$final_parent" != "$publication_root" ] || \
   [ -z "$final_name" ]; then
  echo "Performance publication paths escape the controlled root" >&2
  exit 2
fi

for required_file in invocation.tsv summary.tsv samples.tsv stage-summary.tsv \
  allocation-summary.tsv
do
  [ -s "$staging_result/$required_file" ] || {
    echo "Completed performance evidence is missing $required_file" >&2
    exit 2
  }
done
[ -d "$staging_result/raw" ] || {
  echo "Completed performance evidence is missing raw runs" >&2
  exit 2
}
actual_result=$(awk -F '\t' '$1 == "result" { print $2; found=1; exit }
  END { if (!found) exit 1 }' "$staging_result/invocation.tsv")
actual_result_name=$(awk -F '\t' '$1 == "result-name" { print $2; found=1; exit }
  END { if (!found) exit 1 }' "$staging_result/invocation.tsv")
if [ "$actual_result" != "$expected_result" ] || \
   [ "$actual_result_name" != "$final_name" ]; then
  echo "Performance publication result or result name does not match invocation evidence" >&2
  exit 1
fi

archive_root="$publication_root/$final_name-archive"
archive_label=$(date -u '+%Y%m%dT%H%M%SZ')-$$
archive_path="$archive_root/$archive_label"
previous_evidence=-
mkdir -p "$archive_root"
[ ! -e "$archive_path" ] || {
  echo "Performance archive destination already exists" >&2
  exit 2
}
if [ -e "$final_result" ]; then
  previous_evidence=$archive_path
fi
printf 'key\tvalue\npublished-at\t%s\nresult\t%s\nprevious-evidence\t%s\npublication\tTRANSACTIONAL-PASS\n' \
  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$actual_result" \
  "$previous_evidence" > "$staging_result/publication.tsv"

if [ "$previous_evidence" != - ]; then
  mv "$final_result" "$archive_path"
fi
if ! mv "$staging_result" "$final_result"; then
  if [ "$previous_evidence" != - ] && [ -d "$archive_path" ]; then
    mv "$archive_path" "$final_result" || true
  fi
  echo "Failed to publish completed performance evidence" >&2
  exit 1
fi

echo "Performance evidence transaction published: $actual_result"
