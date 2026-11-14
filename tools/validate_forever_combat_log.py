#!/usr/bin/env python3
"""Check controlled healing captures against the Forever 70938 models."""

import argparse
import csv
import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from statistics import median


@dataclass(frozen=True)
class Model:
    name: str
    ticks: int
    interval: int
    coefficient: float


WILD_GROWTH = Model("Wild Growth", 7, 1, 0.462)
RIPTIDE = Model("Riptide", 5, 3, 0.500)
MODELS = {
    408120: WILD_GROWTH, 1238214: WILD_GROWTH, 1238215: WILD_GROWTH,
    408521: RIPTIDE, 1239242: RIPTIDE, 1239243: RIPTIDE,
}
CRIT_MULTIPLIER = 1.5
TIMING_TOLERANCE = 0.250
HEAL_EVENTS = (
    "SPELL_PERIODIC_HEAL", "SPELL_AURA_APPLIED", "SPELL_AURA_REFRESH",
    "SPELL_AURA_REMOVED", "SPELL_AURA_APPLIED_DOSE", "SPELL_AURA_REMOVED_DOSE",
)
SESSION_EVENTS = {"MAP_CHANGE", "ZONE_CHANGE", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD"}
TIMESTAMP = re.compile(
    r"(?P<date>\d{1,2}/\d{1,2}/\d{4} \d{1,2}:\d{2}:\d{2}\.\d{3})"
    r"(?P<offset>[+-](?:\d{4}|\d{1,2}))\s{2,}(?P<payload>\S.*)"
)


@dataclass(frozen=True)
class Heal:
    time: datetime
    amount: int
    critical: bool
    absorbed: int


@dataclass
class Aura:
    applied: datetime
    removed: datetime | None = None
    ticks: list[Heal] = field(default_factory=list)


@dataclass
class Capture:
    casts: list[Aura] = field(default_factory=list)
    discarded: int = 0
    positive_direct_heals: int = 0


class InvalidLog(ValueError):
    """The selected capture cannot be interpreted under the supported format."""


def timestamp(row):
    match = TIMESTAMP.fullmatch(row.rstrip("\r\n"))
    if not match:
        raise InvalidLog("unsupported combat-log timestamp")
    date = datetime.strptime(match["date"], "%m/%d/%Y %H:%M:%S.%f")
    offset = match["offset"]
    digits = offset[1:]
    if len(digits) == 4:
        hours, minutes = int(digits[:2]), int(digits[2:])
        if minutes >= 60:
            raise InvalidLog("invalid timestamp offset")
    else:
        hours, minutes = int(digits), 0
    sign = -1 if offset.startswith("-") else 1
    return date.replace(tzinfo=timezone(sign * timedelta(hours=hours, minutes=minutes))), match["payload"]


def check_header(fields):
    if (
        len(fields) != 8
        or fields[:5] != ["COMBAT_LOG_VERSION", "22", "ADVANCED_LOG_ENABLED", "1", "BUILD_VERSION"]
        or fields[5] not in {"1.60.1", "1.60.1.70938"}
        or fields[6:] != ["PROJECT_ID", "18"]
    ):
        raise InvalidLog("expected a Forever 1.60.1 advanced combat-log header (v22, project 18)")


def parse_heal(fields, when):
    if len(fields) != 36 or fields[35] not in {"1", "nil"}:
        raise InvalidLog(f"unsupported advanced {fields[0]} layout")
    try:
        effective, amount, overheal, absorbed = map(int, fields[31:35])
    except ValueError:
        raise InvalidLog(f"invalid {fields[0]} healing amounts") from None
    if not (0 <= effective <= amount and 0 <= overheal <= amount and absorbed >= 0):
        raise InvalidLog(f"invalid {fields[0]} healing amounts")
    return Heal(when, amount, fields[35] == "1", absorbed)


def read_capture(path, spell, caster, recipient):
    capture = Capture()
    model = MODELS[int(spell)]
    heal_events = (*HEAL_EVENTS, "SPELL_HEAL") if model is RIPTIDE else HEAL_EVENTS
    aura = None
    have_header = False
    last_time = None

    def finish():
        nonlocal aura
        if aura is None:
            return
        if aura.removed is None:
            capture.discarded += 1
        else:
            capture.casts.append(aura)
        aura = None

    def invalidate():
        nonlocal aura
        if aura is not None:
            capture.discarded += 1
            aura = None

    def past_expiry(when, tolerance=0):
        return (aura is not None and aura.removed is not None
                and (when - aura.removed).total_seconds() > tolerance)

    with path.open(encoding="utf-8-sig") as stream:
        for line_number, row in enumerate(stream, 1):
            if not row.strip():
                continue
            try:
                when, payload = timestamp(row)
                fields = next(csv.reader([payload], escapechar="\\", strict=True))
                event = fields[0]
                if last_time is not None and when < last_time:
                    raise InvalidLog("timestamps move backwards")
                last_time = when
                if event == "COMBAT_LOG_VERSION":
                    check_header(fields)
                    if past_expiry(when, TIMING_TOLERANCE):
                        finish()
                    invalidate()
                    have_header = True
                    continue
                if not have_header:
                    raise InvalidLog("missing Forever advanced combat-log header before events")
                died = event in {"UNIT_DIED", "UNIT_DESTROYED"} and fields[5] in {caster, recipient}
                removed = (event in {"SPELL_DISPEL", "SPELL_STOLEN"} and fields[5] == recipient
                           and fields[12] == spell)
                if event in SESSION_EVENTS or died or removed:
                    if past_expiry(when, TIMING_TOLERANCE):
                        finish()
                    invalidate()
                    continue
                if event not in heal_events or fields[1] != caster or fields[5] != recipient:
                    continue
                if fields[9] != spell:
                    if fields[9].isdecimal() and MODELS.get(int(fields[9])) is model:
                        if event in {"SPELL_AURA_APPLIED", "SPELL_AURA_REFRESH"}:
                            if past_expiry(when):
                                finish()
                            invalidate()
                    continue
                if event in {"SPELL_HEAL", "SPELL_PERIODIC_HEAL"}:
                    heal = parse_heal(fields, when)
                    if event == "SPELL_HEAL":
                        if heal.amount > 0:
                            capture.positive_direct_heals += 1
                    elif aura is not None:
                        aura.ticks.append(heal)
                    continue
                if fields[12] != "BUFF":
                    raise InvalidLog("expected BUFF for the selected healing aura")
                if event == "SPELL_AURA_APPLIED":
                    if past_expiry(when):
                        finish()
                    if aura is None:
                        aura = Aura(when)
                    else:
                        # A duplicate or same-time reapplication cannot be separated from prior ticks.
                        invalidate()
                elif event == "SPELL_AURA_REMOVED":
                    if aura is not None:
                        if aura.removed is None:
                            aura.removed = when
                        else:
                            invalidate()
                else:
                    # Refresh and stack events leave the original tick ordinals uncertain.
                    if past_expiry(when):
                        finish()
                    invalidate()
            except (IndexError, ValueError, csv.Error) as error:
                reason = str(error) if isinstance(error, InvalidLog) else "malformed timestamp or event fields"
                raise InvalidLog(f"line {line_number}: {reason}") from None
    if not have_header:
        raise InvalidLog("missing Forever advanced combat-log header")
    finish()
    return capture


def select_complete(capture, model):
    complete = []
    problems = []
    for aura in capture.casts:
        duration = (aura.removed - aura.applied).total_seconds()
        expected_duration = model.ticks * model.interval
        if duration < expected_duration - TIMING_TOLERANCE:
            capture.discarded += 1
        elif len(aura.ticks) != model.ticks:
            problems.append(f"expected {model.ticks} ticks, observed {len(aura.ticks)}")
        elif duration > expected_duration + TIMING_TOLERANCE or any(
            abs((tick.time - aura.applied).total_seconds() - index * model.interval) > TIMING_TOLERANCE
            for index, tick in enumerate(aura.ticks, 1)
        ):
            problems.append(f"expected ticks every {model.interval} s and expiry at {expected_duration} s")
        else:
            complete.append(aura.ticks)
    return complete, problems


def gain_check(low, high, model, power_delta):
    expected = power_delta * model.coefficient
    totals = [
        [sum(tick.amount for tick in cast) for cast in captures
         if all(tick.amount > 0 and not tick.critical and not tick.absorbed for tick in cast)]
        for captures in (low, high)
    ]
    low_totals, high_totals = totals
    if not low_totals or not high_totals:
        return 3, "need a complete noncritical, unabsorbed cast with positive raw healing at each power"
    minimum_gain = min(high_totals) - max(low_totals)
    maximum_gain = max(high_totals) - min(low_totals)
    observed = median(high_totals) - median(low_totals)
    status = 0 if expected - model.ticks <= minimum_gain <= maximum_gain <= expected + model.ticks else 2
    return status, (
        f"observed {observed:g} total healing gain (range {minimum_gain:g} to {maximum_gain:g}), "
        f"expected {expected:g} ± {model.ticks} per recipient"
    )


def crit_check(low, high, model):
    matched = 0
    outliers = 0
    for captures in (low, high):
        unabsorbed = [cast for cast in captures if not any(tick.absorbed for tick in cast)]
        for index in range(model.ticks):
            ticks = [cast[index] for cast in unabsorbed]
            normal = [tick.amount for tick in ticks if not tick.critical and tick.amount > 2]
            if not normal:
                continue
            minimum, maximum = min(normal), max(normal)
            for tick in ticks:
                if tick.critical:
                    matched += 1
                    if (abs(tick.amount - minimum * CRIT_MULTIPLIER) > 1
                            or abs(tick.amount - maximum * CRIT_MULTIPLIER) > 1):
                        outliers += 1
    if not matched:
        return 3, "need a critical and noncritical tick at the same healing power and tick number"
    return 2 if outliers else 0, (
        f"{matched - outliers}/{matched} matched critical ticks within 1 healing of {CRIT_MULTIPLIER:g}×"
    )


def check_initial_heal(low, high, captures):
    low_heals, high_heals = (capture.positive_direct_heals for capture in captures)
    if low_heals or high_heals:
        return 2, f"expected no positive SPELL_HEAL events, observed low {low_heals}, high {high_heals}"
    if not low or not high:
        return 3, "need a complete aura at each healing-power value"
    return 0, "no positive SPELL_HEAL events in either capture"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=int, choices=[70938], required=True,
                        help="numeric build confirmed independently for both captures")
    parser.add_argument("--spell-id", type=int, choices=MODELS, required=True)
    parser.add_argument("--caster-guid", required=True)
    parser.add_argument("--recipient-guid", required=True)
    for level in ("low", "high"):
        parser.add_argument(f"--{level}-log", type=Path, required=True)
        parser.add_argument(f"--{level}-healing-power", type=int, required=True)
    args = parser.parse_args()
    power_delta = args.high_healing_power - args.low_healing_power
    if args.low_healing_power < 0 or power_delta < 50:
        parser.error("use nonnegative healing-power values at least 50 points apart, low then high")
    spell = str(args.spell_id)
    model = MODELS[args.spell_id]
    captures = []
    try:
        if args.low_log.samefile(args.high_log):
            parser.error("the low and high captures must be distinct files")
    except OSError:
        parser.error("both capture files must be readable")
    for label, path in (("low", args.low_log), ("high", args.high_log)):
        try:
            captures.append(read_capture(path, spell, args.caster_guid, args.recipient_guid))
        except (OSError, UnicodeError, InvalidLog) as error:
            reason = str(error) if isinstance(error, InvalidLog) else "file is unreadable as UTF-8 text"
            parser.error(f"{label} capture: {reason}")

    low, low_problems = select_complete(captures[0], model)
    high, high_problems = select_complete(captures[1], model)
    problems = low_problems + high_problems
    if problems:
        schedule = (2, f"{len(problems)} mismatched casts. First mismatch: {problems[0]}")
    elif not low or not high:
        schedule = (3, "need a complete aura at each healing-power value")
    else:
        schedule = (0, f"{model.ticks} ticks per recipient, {model.interval} s apart")
    checks = [
        ("Tick count and timing", schedule),
        ("Healing-power gain", gain_check(low, high, model, power_delta)),
        ("Periodic crit multiplier", crit_check(low, high, model)),
    ]
    if model is RIPTIDE:
        checks.append(("Initial heal absence", check_initial_heal(low, high, captures)))
    print(f"{model.name} ({spell}), declared Forever build {args.build}")
    print(f"Complete matching casts: low {len(low)}, high {len(high)}. "
          f"Incomplete or ambiguous casts skipped: low {captures[0].discarded}, high {captures[1].discarded}.")
    status_names = {0: "PASS", 2: "FAIL", 3: "INCONCLUSIVE"}
    for label, (status, message) in checks:
        print(f"{status_names[status]} {label}: {message}")
    if model is RIPTIDE:
        print("N/A Initial healing-power gain: Riptide has no initial heal on build 70938")
        print("N/A Initial crit multiplier: Riptide has no initial heal on build 70938")
    statuses = {status for _, (status, _) in checks}
    return 2 if 2 in statuses else max(statuses)


if __name__ == "__main__":
    raise SystemExit(main())
