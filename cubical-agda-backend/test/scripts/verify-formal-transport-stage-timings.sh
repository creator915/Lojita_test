#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
expected_engine=${STAGE_TIMING_ENGINE:-nbe}
case "$expected_engine" in
  agda-baseline|nbe) ;;
  *) echo "Invalid stage timing engine: $expected_engine" >&2; exit 2 ;;
esac
if [ "$expected_engine" = agda-baseline ]; then
  default_root="$backend_dir/build/agda29/formal-transport"
else
  default_root="$backend_dir/build/agda29/formal-transport-nbe"
fi
evidence_root=${STAGE_TIMING_EVIDENCE_ROOT:-$default_root}
result_dir=${STAGE_TIMING_RESULT_DIR:-$backend_dir/build/agda29/formal-transport-stage-timings/$expected_engine}
groups='base glue int core boundary hit higher monolithic'

[ -d "$evidence_root" ] || {
  echo "Stage timing evidence root is missing: $evidence_root" >&2
  exit 2
}

temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/formal-stage-timings.XXXXXX")
cleanup() {
  rm -rf "$temporary_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$result_dir"
samples="$result_dir/samples.tsv"
summary="$result_dir/summary.tsv"
printf 'engine\tgroup\tscenario\tstage\telapsed_seconds\tstatus\n' > "$samples"

group_count=0
timed_scenario_count=0
for group in $groups
do
  group_dir="$evidence_root/$group"
  for required_file in summary.tsv binding-time.tsv invocation.tsv stage-timings.tsv
  do
    [ -s "$group_dir/$required_file" ] || {
      echo "$group is missing stage timing input $required_file" >&2
      exit 2
    }
  done
  actual_engine=$(awk -F '\t' '$1 == "engine" { print $2; found=1; exit }
    END { if (!found) exit 1 }' "$group_dir/invocation.tsv")
  [ "$actual_engine" = "$expected_engine" ] || {
    echo "$group stage timing engine mismatch: $actual_engine" >&2
    exit 1
  }

  timed_scenarios="$temporary_dir/$group.timed-scenarios"
  awk -F '\t' 'NR > 1 && $6 != "-" { print $1 }' \
    "$group_dir/summary.tsv" | LC_ALL=C sort > "$timed_scenarios"
  group_timed_count=$(wc -l < "$timed_scenarios" | tr -d ' ')
  [ "$group_timed_count" -gt 0 ] || {
    echo "$group has no timed scenarios" >&2
    exit 1
  }

  timing_scenarios="$temporary_dir/$group.timing-scenarios"
  awk -F '\t' 'NR > 1 { seen[$1]=1 } END { for (s in seen) print s }' \
    "$group_dir/stage-timings.tsv" | LC_ALL=C sort > "$timing_scenarios"
  cmp -s "$timed_scenarios" "$timing_scenarios" || {
    echo "$group stage timing scenarios differ from timed formal cases" >&2
    exit 1
  }

  if ! awk -F '\t' -v engine="$expected_engine" '
    FILENAME == ARGV[1] {
      if (FNR > 1) binding[$1]=$2
      next
    }
    FNR == 1 {
      if ($0 != "scenario\tstage\telapsed_seconds\tstatus") exit 2
      next
    }
    {
      scenario=$1; stage=$2; elapsed=$3; status=$4
      allowed = stage == "engine-total" || stage == "nbe-evaluation" ||
        stage == "nbe-readback" || stage == "engine-result-admission" ||
        stage == "internal-semantic-audit" || stage == "treeless-conversion" ||
        stage == "residualization" || stage == "scheme-codegen-publication" ||
        stage == "agda-frontend-module-loading" || stage == "chez-execution" ||
        stage == "typed-residual-consumer-execution"
      if (!allowed || seen[scenario SUBSEP stage]++) exit 3
      if ((status == "measured" || status == "derived-remainder") &&
          elapsed !~ /^[0-9]+([.][0-9]+)?$/) exit 4
      if (status == "not-applicable" && elapsed != "-") exit 5
      if (status != "measured" && status != "derived-remainder" &&
          status != "not-applicable") exit 6
      rows[scenario]++
      state[scenario SUBSEP stage]=status
    }
    END {
      for (scenario in rows) {
        if (rows[scenario] != 11 || binding[scenario] == "") exit 7
        if (state[scenario SUBSEP "engine-total"] != "measured" ||
            state[scenario SUBSEP "engine-result-admission"] != "measured" ||
            state[scenario SUBSEP "internal-semantic-audit"] != "measured" ||
            state[scenario SUBSEP "treeless-conversion"] != "measured" ||
            state[scenario SUBSEP "agda-frontend-module-loading"] != "derived-remainder") exit 8
        if (engine == "agda-baseline" &&
            (state[scenario SUBSEP "nbe-evaluation"] != "not-applicable" ||
             state[scenario SUBSEP "nbe-readback"] != "not-applicable")) exit 9
        if (engine == "nbe" &&
            state[scenario SUBSEP "nbe-evaluation"] != "measured") exit 10
        if (binding[scenario] == "static") {
          if (state[scenario SUBSEP "residualization"] != "not-applicable" ||
              state[scenario SUBSEP "scheme-codegen-publication"] != "measured" ||
              state[scenario SUBSEP "chez-execution"] != "measured" ||
              state[scenario SUBSEP "typed-residual-consumer-execution"] != "not-applicable") exit 11
        } else if (binding[scenario] == "dynamic") {
          if (state[scenario SUBSEP "residualization"] != "measured" ||
              state[scenario SUBSEP "scheme-codegen-publication"] != "not-applicable") exit 12
          if (scenario ~ /-file$/ || scenario ~ /-pipe$/) {
            if (state[scenario SUBSEP "chez-execution"] != "not-applicable" ||
                state[scenario SUBSEP "typed-residual-consumer-execution"] != "measured") exit 13
          } else if (state[scenario SUBSEP "chez-execution"] != "not-applicable" ||
                     state[scenario SUBSEP "typed-residual-consumer-execution"] != "not-applicable") exit 14
        } else exit 15
      }
    }
  ' "$group_dir/binding-time.tsv" "$group_dir/stage-timings.tsv"
  then
    echo "$group stage timing contract failed" >&2
    exit 1
  fi

  awk -F '\t' -v engine="$expected_engine" -v group="$group" \
    'NR > 1 { print engine "\t" group "\t" $0 }' \
    "$group_dir/stage-timings.tsv" >> "$samples"
  group_count=$((group_count + 1))
  timed_scenario_count=$((timed_scenario_count + group_timed_count))
done

[ "$group_count" -eq 8 ] || {
  echo "Stage timing evidence did not cover eight formal groups" >&2
  exit 1
}
[ "$timed_scenario_count" -eq 40 ] || {
  echo "Stage timing evidence expected 40 timed scenarios, found $timed_scenario_count" >&2
  exit 1
}

awk -F '\t' '
  NR == 1 { next }
  {
    key=$1 SUBSEP $4
    total[key]++
    engine[key]=$1
    stage[key]=$4
    if ($6 == "measured" || $6 == "derived-remainder") {
      measured[key]++
      seconds[key]+=$5
      if (!(key in minimum) || $5 < minimum[key]) minimum[key]=$5
      if (!(key in maximum) || $5 > maximum[key]) maximum[key]=$5
    } else {
      notApplicable[key]++
    }
  }
  END {
    print "engine\tstage\tmeasured_count\tnot_applicable_count\ttotal_seconds\tmean_seconds\tmin_seconds\tmax_seconds"
    for (key in total) {
      mean = measured[key] ? seconds[key] / measured[key] : 0
      min = measured[key] ? minimum[key] : "-"
      max = measured[key] ? maximum[key] : "-"
      printf "%s\t%s\t%d\t%d\t%.9f\t%.9f\t%s\t%s\n", \
        engine[key],stage[key],measured[key]+0,notApplicable[key]+0,
        seconds[key]+0,mean,min,max
    }
  }
' "$samples" | {
  IFS= read -r header
  printf '%s\n' "$header"
  LC_ALL=C sort
} > "$summary"

echo "Formal stage timing contract PASS ($expected_engine, 8 groups, 40 timed scenarios)"
