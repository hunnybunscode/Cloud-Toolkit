#!/usr/bin/env bash
# Lists EBS volumes with numbering and a post-table selector menu.
# Columns: # | EBS Volume | Attached EC2 (20 chars) | Encrypted | Active | Date Created
# Robust JSON handling, batches instance lookups, Python 3.6 compatible date parsing.

set -euo pipefail

print_header(){ echo -e "\n━━━━━━━━━━━━━━━━ $1 ━━━━━━━━━━━━━━━━"; }
ok(){ echo "✅ $*"; }
warn(){ echo "⚠️  $*" >&2; }
fail(){ echo "❌ $*" >&2; return 1; }

_is_json_file() {
  python3 - "$1" <<'PY'
import sys, json, pathlib
p = pathlib.Path(sys.argv[1])
try:
    with p.open() as f: json.load(f)
    sys.exit(0)
except Exception:
    sys.exit(1)
PY
}

# Parse user selection like: "1,3-5 9"
# -> prints the chosen indices (space-separated) to stdout, validated 1..N
_parse_selection() {
  local input="$1" max="$2"
  # Normalize: commas -> spaces
  input="${input//,/ }"
  local out=() tok lo hi n
  for tok in $input; do
    if [[ "$tok" =~ ^[0-9]+-[0-9]+$ ]]; then
      lo="${tok%-*}"; hi="${tok#*-}"
      if (( lo<1 || hi>max || lo>hi )); then fail "Invalid range: $tok"; return 1; fi
      for ((n=lo;n<=hi;n++)); do out+=("$n"); done
    elif [[ "$tok" =~ ^[0-9]+$ ]]; then
      n="$tok"; (( n>=1 && n<=max )) || { fail "Invalid index: $n"; return 1; }
      out+=("$n")
    else
      fail "Bad token: $tok"; return 1
    fi
  done
  # uniq while preserving order
  awk 'BEGIN{FS=OFS=" "} {for(i=1;i<=NF;i++){if(!seen[$i]++){printf("%s%s",$i,(i==NF?"":" "))}} print ""}' <<<"${out[*]}"
}

action_encrypt_ebs() {
  print_header "EBS Inventory — # | Volume | Attached EC2 (20 chars) | Encrypted | Active | Date Created"
  local REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-gov-west-1}}"

  local vols_file ids_file map_file idx_file
  vols_file="$(mktemp)"
  ids_file="$(mktemp)"
  map_file="$(mktemp)"   # TSV: "<instance-id>\t<Name or ID>"
  idx_file="$(mktemp)"   # TSV: "<row#>\t<VolumeId>"
  trap 'rm -f "$vols_file" "$ids_file" "$map_file" "$idx_file"' EXIT

  # 1) Describe volumes -> file
  if ! err_vols="$(aws ec2 describe-volumes \
      --region "$REGION" \
      --no-cli-pager \
      --query 'Volumes[].{VolumeId:VolumeId,Encrypted:Encrypted,State:State,CreateTime:CreateTime,Attachments:Attachments}' \
      --output json > "$vols_file" 2>&1)"; then
    echo "❌ describe-volumes failed:"; echo "$err_vols"; return 1
  fi
  if ! _is_json_file "$vols_file"; then
    echo "❌ describe-volumes did not produce valid JSON. Raw begins with:"; head -n 40 "$vols_file"
    echo; echo "stderr:"; echo "$err_vols"
    echo; echo "Try: aws ec2 describe-volumes --region $REGION --no-cli-pager --output json --debug"
    return 1
  fi

  # 2) Collect unique instance IDs (for Name tag mapping)
  if ! aws ec2 describe-volumes \
      --region "$REGION" \
      --no-cli-pager \
      --query 'Volumes[].Attachments[].InstanceId' \
      --output text > "$ids_file" 2>/dev/null; then
    warn "Could not collect instance IDs"
    : > "$ids_file"
  fi
  mapfile -t id_array < <(tr '\t ' '\n' < "$ids_file" | sed '/^$/d' | sort -u)

  # 3) Build InstanceId -> Name map in batches (100 IDs per call)
  : > "$map_file"
  if ((${#id_array[@]})); then
    local batch=() count=0
    for iid in "${id_array[@]}"; do
      batch+=("$iid"); count=$((count+1))
      if ((count==100)); then
        aws ec2 describe-instances \
          --region "$REGION" --no-cli-pager \
          --instance-ids "${batch[@]}" \
          --query 'Reservations[].Instances[].{InstanceId:InstanceId, Name: Tags[?Key==`Name`]|[0].Value}' \
          --output text 2>/dev/null \
          | awk '{id=$1; $1=""; sub(/^ /,""); name=$0; if (name==""||name=="None") name=id; print id "\t" name}' >> "$map_file" || true
        batch=(); count=0
      fi
    done
    if ((${#batch[@]})); then
      aws ec2 describe-instances \
        --region "$REGION" --no-cli-pager \
        --instance-ids "${batch[@]}" \
        --query 'Reservations[].Instances[].{InstanceId:InstanceId, Name: Tags[?Key==`Name`]|[0].Value}' \
        --output text 2>/dev/null \
        | awk '{id=$1; $1=""; sub(/^ /,""); name=$0; if (name==""||name=="None") name=id; print id "\t" name}' >> "$map_file" || true
    fi
  fi

  # 4) Print table with numbering; also emit index file (# -> VolumeId)
  EBS_INDEX_FILE="$idx_file" python3 - "$vols_file" "$map_file" <<'PY'
import os, sys, json, re
from datetime import datetime

vols_path, map_path = sys.argv[1], sys.argv[2]
with open(vols_path) as f: volumes = json.load(f)

# id->name map
inst_name = {}
try:
    with open(map_path) as mf:
        for line in mf:
            line=line.rstrip("\n")
            if not line: continue
            parts = line.split("\t", 1)
            if len(parts)==2:
                inst_name[parts[0]] = parts[1]
except Exception:
    pass

def normalize_tz(s: str) -> str:
    return re.sub(r'([+-]\d{2}):(\d{2})$', r'\1\2', s)

def parse_iso(s):
    if not s: return None
    s = normalize_tz(s)
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f%z","%Y-%m-%dT%H:%M:%S%z","%Y-%m-%dT%H:%M:%S.%fZ","%Y-%m-%dT%H:%M:%SZ"):
        try: return datetime.strptime(s, fmt)
        except Exception: pass
    return None

def fmt_date(s):
    dt = parse_iso(s)
    if not dt: return "-"
    try: return dt.strftime("%-m/%-d/%Y")
    except Exception: return dt.strftime("%m/%d/%Y").lstrip("0").replace("/0","/")

def trunc20(s):
    if s is None: return "-"
    s = str(s)
    return s[:20]

rows = []
for v in volumes:
    atts = v.get("Attachments") or [{}]
    for a in atts:
        iid = a.get("InstanceId")
        name = trunc20(inst_name.get(iid, iid) if iid else "-")
        rows.append({
            "#": 0,  # placeholder; we number after sorting
            "EBS Volume":   v.get("VolumeId","-"),
            "Attached EC2": name,
            "Encrypted":    "yes" if v.get("Encrypted") else "no",
            "Active":       "yes" if v.get("State") == "in-use" else "no",
            "Date Created": fmt_date(v.get("CreateTime")),
        })

# Sort: unencrypted first, then by name, then by vol id
rows.sort(key=lambda r: (r["Encrypted"] != "no", r["Attached EC2"], r["EBS Volume"]))

# Number rows and write index map
idx_path = os.environ.get("EBS_INDEX_FILE")
if idx_path:
    with open(idx_path, "w") as idxf:
        for i, r in enumerate(rows, start=1):
            r["#"] = i
            idxf.write(f"{i}\t{r['EBS Volume']}\n")

cols = ["#","EBS Volume","Attached EC2","Encrypted","Active","Date Created"]
widths = {c: max(len(c), max((len(str(r[c])) for r in rows), default=0)) for c in cols}

def line(ch="-"): return "  ".join(ch * widths[c] for c in cols)
print("  ".join(c.ljust(widths[c]) for c in cols))
print(line("-"))
for r in rows:
    print("  ".join(str(r[c]).ljust(widths[c]) for c in cols))
print(f"\nSummary: total {len({r['EBS Volume'] for r in rows})}, unencrypted {len({r['EBS Volume'] for r in rows if r['Encrypted']=='no'})}")
PY

  # 5) Post-table selector menu
  echo
  echo "Actions:"
  echo "  [1] Select EBS volumes to encrypt"
  echo "  [2] Upload Lambda to notify OrgBox on unencrypted EBS creation"
  echo "  [3] Return to main menu"
  echo "  [0] Exit"
  read -rp "Choose an option [0-3]: " choice

  case "${choice:-}" in
    1)
      # User selects by numbers
      read -rp "Enter volume numbers (e.g., 1,3-5 9): " sel
      # Count rows to validate
      local max_rows
      max_rows="$(wc -l < "$idx_file")"
      # idx_file has one line per row (# + tab + VolumeId), so lines==rows
      if [[ -z "${sel//[[:space:]]/}" ]]; then fail "No selection entered"; return 1; fi
      indices=$(_parse_selection "$sel" "$max_rows") || return 1

      # Map indices -> VolumeIds
      # Build regex like: ^(1|3|4|5|9)\t
      regex="^($(tr ' ' '|' <<<"$indices"))\t"
      selected="$(grep -E "$regex" "$idx_file" | cut -f2)"
      if [[ -z "$selected" ]]; then fail "No matching rows found"; return 1; fi

      echo "Selected VolumeIds:"
      echo "$selected" | sed 's/^/  - /'
      echo
      ok "Selection captured. Next step would be: snapshot → copy-encrypt → create encrypted vol → swap."
      ;;

    2)
      print_header "Upload Lambda (notify OrgBox on unencrypted EBS creation)"
      echo "This is a placeholder. Wire this to your deployment script (e.g., action_deploy_notify_lambda.sh)."
      echo "Suggested next steps:"
      echo "  • Create EventBridge rule on CreateVolume or ModifyVolume (Encrypted=false)"
      echo "  • Lambda posts to OrgBox webhook with volume details"
      ok "Stub completed."
      ;;

    3)
      ok "Returning to main menu."
      return 0
      ;;

    0)
      echo "Bye."
      exit 0
      ;;

    *)
      warn "Invalid selection."
      ;;
  esac
}

