"""Generate FSRS-6 reference test vectors for the Quizly C# port.

Uses the reference implementation py-fsrs (pip package `fsrs`) with the exact
scheduler configuration Quizly uses: default parameters, desired retention 0.9,
learning steps 1m/10m, relearning step 10m, maximum interval 36500, fuzz OFF.
Only the ratings Again (1) and Good (3) are used.

Usage (in a throwaway virtualenv):
    pip install fsrs==6.3.2
    python docs/fsrs/generate_vectors.py > docs/fsrs/fsrs6-reference-vectors.json
"""

import json
import sys
from datetime import datetime, timedelta, timezone
from importlib.metadata import version

from fsrs import Card, Rating, Scheduler, State

START = datetime(2026, 11, 2, 7, 0, 0, tzinfo=timezone.utc)

scheduler = Scheduler(enable_fuzzing=False)


def iso(dt):
    return None if dt is None else dt.isoformat().replace("+00:00", "Z")


def snapshot(card):
    return {
        "state": card.state.name,
        "step": card.step,
        "stability": card.stability,
        "difficulty": card.difficulty,
        "due": iso(card.due),
        "lastReview": iso(card.last_review),
    }


def run(name, description, plan):
    """plan: list of (rating, when) where when is
    "due"                 -> review exactly at the card's due time
    ("due+", timedelta)   -> review at due + offset (late, or early if negative)
    ("abs", datetime)     -> review at an absolute time
    """
    card = Card(card_id=1, due=START)
    steps = []
    for rating, when in plan:
        if when == "due":
            at = card.due
        elif when[0] == "due+":
            at = card.due + when[1]
        else:
            at = when[1]
        before = snapshot(card)
        retrievability = scheduler.get_card_retrievability(card, at)
        elapsed_days = (at - card.last_review).days if card.last_review else 0
        card, _ = scheduler.review_card(card, rating, at)
        steps.append(
            {
                "reviewedAt": iso(at),
                "rating": int(rating),
                "before": before,
                "retrievabilityBefore": retrievability,
                "elapsedDays": elapsed_days,
                "scheduledDays": (card.due - at).days if card.state == State.Review else 0,
                "after": snapshot(card),
            }
        )
    return {"name": name, "description": description, "steps": steps}


A, G = Rating.Again, Rating.Good

# Good at START (moves to the 10 min step), Good 10 min later -> graduates to Review.
GRADUATED_AT = START + timedelta(minutes=10)

cases = [
    run(
        "good_only",
        "New card answered Good at every due time.",
        [(G, "due")] * 8,
    ),
    run(
        "again_first",
        "New card: Again, then Good at every due time.",
        [(A, "due")] + [(G, "due")] * 6,
    ),
    run(
        "again_twice_in_learning",
        "Again, Good, Again inside the learning steps, then Good.",
        [(A, "due"), (G, "due"), (A, "due")] + [(G, "due")] * 5,
    ),
    run(
        "lapse_and_relearn",
        "Graduates, lapses with Again in Review, relearns with Good.",
        [(G, "due")] * 4 + [(A, "due")] + [(G, "due")] * 4,
    ),
    run(
        "repeated_lapses",
        "Several lapses in a row from Review and Relearning.",
        [(G, "due")] * 3 + [(A, "due"), (A, "due"), (G, "due"), (A, "due")] + [(G, "due")] * 3,
    ),
    run(
        "overdue_reviews",
        "Reviews done much later than due (retrievability well below 0.9).",
        [(G, "due"), (G, "due"), (G, ("due+", timedelta(days=10))), (G, ("due+", timedelta(days=40))),
         (A, ("due+", timedelta(days=90))), (G, "due"), (G, ("due+", timedelta(days=5)))],
    ),
    run(
        "same_day_in_review",
        "Review-state card reviewed again 3 h and 5 h after graduating (short-term stability).",
        [(G, "due"), (G, "due"), (G, ("abs", GRADUATED_AT + timedelta(hours=3))),
         (A, ("abs", GRADUATED_AT + timedelta(hours=5))), (G, "due"), (G, "due")],
    ),
    run(
        "early_reviews",
        "Reviews done before the card is due.",
        [(G, "due"), (G, "due"), (G, ("due+", -timedelta(days=1))), (G, ("due+", -timedelta(days=3))),
         (A, ("due+", -timedelta(days=2))), (G, "due")],
    ),
]

output = {
    "generator": f"py-fsrs {version('fsrs')}",
    "scheduler": scheduler.to_dict(),
    "notes": [
        "A never-reviewed card is state Learning, step 0, stability/difficulty null, due = creation time.",
        "elapsedDays = whole days (floor) since lastReview; 0 for the first review.",
        "scheduledDays = whole days from reviewedAt to the new due, only in Review state; 0 otherwise.",
        "Review intervals use Python round() = round half to even (MidpointRounding.ToEven in C#).",
    ],
    "cases": cases,
}

json.dump(output, sys.stdout, indent=2)
sys.stdout.write("\n")
