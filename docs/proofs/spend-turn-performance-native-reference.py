#!/usr/bin/env python3
"""Independent offline reference join. Outputs stay in the private proof directory."""
import datetime as dt
import json
import pathlib
import sys

MAX_INT = 2**63 - 1

def integer(value):
    return value if type(value) is int and 0 <= value < MAX_INT else None

def counters(value):
    if not isinstance(value, dict):
        return None
    values = [integer(value.get(key, default)) for key, default in (
        ("input_tokens", None), ("output_tokens", None),
        ("cached_input_tokens", 0), ("reasoning_output_tokens", 0))]
    if None in values:
        return None
    inp, out, cached, reasoning = values
    if cached > inp or reasoning > out or inp + out > MAX_INT:
        return None
    return values

def at_least(total, request):
    return total is not None and all(a >= b for a, b in zip(total, request))

def timestamp(value):
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None

def evidence(value):
    return value.strip() if isinstance(value, str) and value.strip() else None

root = pathlib.Path(sys.argv[1])
samples = []
raw_candidates = []
audit = {"files": 0, "bytes": 0, "malformed_owned_request_rows": 0,
         "rejected_candidate_turns": 0, "real_usage_values": "withheld"}
for path in sorted((root / "sessions").rglob("*.jsonl")):
    audit["files"] += 1
    audit["bytes"] += path.stat().st_size
    owner = None
    execution = None
    active = None
    current_model = None
    turn_models = {}
    responses = set()
    turns = {}
    for line in path.open():
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        payload = obj.get("payload", {})
        if not isinstance(payload, dict):
            continue
        kind = obj.get("type")
        if kind == "session_meta":
            owner = evidence(payload.get("id"))
            execution = owner
            assert not payload.get("forked_from_id"), "Reference corpus must be dependency-closed root sessions"
            continue
        when = timestamp(obj.get("timestamp"))
        if when is None:
            continue
        if kind == "event_msg" and payload.get("type") == "task_started":
            active = evidence(payload.get("turn_id"))
            if active in turns:
                turns[active]["completion"] = None
            continue
        turn = evidence(payload.get("turn_id")) or active
        if not turn:
            continue
        state = turns.setdefault(turn, {"rows": [], "raw_rows": [], "reported": None,
                                       "raw_reported": None, "invalid": False, "completion": None,
                                       "models": set(), "input": 0, "cached": 0, "effort": None, "conflict": False})
        if kind == "turn_context":
            if isinstance(payload.get("model"), str):
                current_model = evidence(payload["model"])
            turn_models[turn] = current_model
            effort = evidence(payload.get("effort"))
            if state["effort"] and state["effort"] != effort:
                state["conflict"] = True
            state["effort"] = effort
        if kind == "event_msg" and payload.get("type") == "task_complete":
            state["completion"] = (obj["timestamp"], when, payload)
        elif kind == "token_usage_record":
            if evidence(payload.get("thread_id")) != owner:
                continue
            session = evidence(payload.get("session_id"))
            if payload.get("session_id") is not None and session != execution:
                continue
            request = counters(payload.get("usage"))
            total = counters(payload.get("thread_token_usage"))
            response = evidence(payload.get("response_id"))
            valid = request is not None and at_least(total, request) and response is not None
            if not valid:
                state["invalid"] = True
                audit["malformed_owned_request_rows"] += 1
            # Lax output-only candidates quantify what full counter validation rejects.
            raw_output = integer((payload.get("usage") or {}).get("output_tokens"))
            raw_total = integer((payload.get("turn_token_usage") or {}).get("output_tokens"))
            if response and response not in responses and raw_output is not None:
                state["raw_rows"].append((when, raw_output))
                state["raw_reported"] = raw_total
            if not valid or response in responses:
                continue
            responses.add(response)
            state["rows"].append((when, request[1]))
            state["input"] += request[0]
            state["cached"] += request[2]
            state["models"].add(evidence(payload.get("model")) or turn_models.get(turn) or "unknown")
            turn_total = counters(payload.get("turn_token_usage"))
            state["reported"] = turn_total[1] if at_least(turn_total, request) else None
    for turn, state in turns.items():
        completion = state["completion"]
        if completion is None:
            continue
        text, completed, payload = completion
        duration = integer(payload.get("duration_ms"))
        if not duration or payload.get("error") is not None:
            continue
        first = integer(payload.get("time_to_first_token_ms"))
        first = first if first is not None and first <= duration else None
        started = integer(payload.get("started_at"))
        started = dt.datetime.fromtimestamp(started, dt.timezone.utc) if started is not None else None
        def complete(rows, reported):
            return bool(rows) and sum(out for _, out in rows) == reported and all(
                when <= completed and (started is None or when >= started) for when, _ in rows)
        candidate = {"session_id": owner, "turn_id": turn, "completed_at": text,
                     "output_tokens": state["reported"], "duration_ms": duration, "first_token_ms": first}
        if complete(state["raw_rows"], state["raw_reported"]):
            raw_candidates.append(candidate)
            if state["invalid"]:
                audit["rejected_candidate_turns"] += 1
        if not state["invalid"] and complete(state["rows"], state["reported"]):
            candidate.update(model=next(iter(state["models"])) if len(state["models"]) == 1 and "unknown" not in state["models"] else None,
                             effort=None if state["conflict"] else state["effort"],
                             input_tokens=state["input"], cached_input_tokens=state["cached"])
            samples.append(candidate)

order = lambda row: (row["completed_at"], row["session_id"], row["turn_id"])
samples.sort(key=order)
expected = sorted(json.loads((root / "expected.json").read_text()), key=order)
assert samples == expected, "Independent reference must exactly match the frozen expected sample set"
audit["output_only_candidates"] = len(raw_candidates)
audit["validated_timed_turns"] = len(samples)
audit["matches_frozen_reference"] = True
(root / "reference-audit.json").write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n")
(root / "reference-recomputed.json").write_text(json.dumps(samples, indent=2) + "\n")
print(json.dumps(audit, sort_keys=True))

