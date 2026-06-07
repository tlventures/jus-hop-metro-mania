/**
 * lib/anti-cheat.js
 * -----------------
 * Server-side plausibility validation for client-reported game scores.
 *
 * The trivia leaderboard ranks on the raw `score` the client submits. Points
 * credited to the wallet are already capped server-side, but the *ranking* is
 * not — without this gate an authenticated user could POST score=100000 and top
 * every leaderboard. This module derives the maximum score that is physically
 * achievable from the reported gameplay and clamps anything above it, recording
 * the event for review.
 *
 * Trivia scoring model (must mirror the Flutter client in trivia_screen.dart):
 *   per correct answer = (10 base + up to 5 speed bonus) * up to 2.0 streak mult
 *                      = 30 points maximum per question.
 * So the ceiling is questionsAnswered * MAX_POINTS_PER_QUESTION. A small grace
 * factor absorbs rounding without opening a meaningful cheating window.
 */

'use strict';

const MAX_POINTS_PER_QUESTION = 30;
const GRACE_FACTOR = 1.05;            // 5% slack for rounding
// Minimum wall-clock seconds a human needs per question. Used only when the
// client reports timeSpent; a score that implies answering faster than this is
// treated as automated/replayed.
const MIN_SECONDS_PER_QUESTION = 1;

/**
 * Validate (and if necessary clamp) a trivia score.
 *
 * @param {object} payload  { score, questionsAnswered, timeSpent }
 * @returns {{ accepted:boolean, score:number, reason:(string|null),
 *             reportedScore:number, maxPlausible:(number|null) }}
 *   accepted   — true when the reported score was within bounds (no tampering)
 *   score      — the value to actually store (clamped when not accepted)
 *   reason     — machine code when clamped (null when accepted)
 *   maxPlausible — the computed ceiling (null when it couldn't be computed)
 */
function validateTriviaScore(payload = {}) {
  const reportedScore = Math.max(0, Math.floor(Number(payload.score) || 0));
  const questionsAnswered = Math.max(
    0,
    Math.floor(Number(payload.questionsAnswered) || 0),
  );
  const timeSpent =
    payload.timeSpent == null ? null : Math.max(0, Number(payload.timeSpent));

  // Can't bound without knowing how many questions were answered. Accept as-is;
  // the Zod schema's absolute 0..100000 cap is the only backstop here.
  if (questionsAnswered <= 0) {
    return {
      accepted: true,
      score: reportedScore,
      reason: null,
      reportedScore,
      maxPlausible: null,
    };
  }

  const maxPlausible = Math.ceil(
    questionsAnswered * MAX_POINTS_PER_QUESTION * GRACE_FACTOR,
  );

  // 1) Score exceeds what the reported number of questions can produce.
  if (reportedScore > maxPlausible) {
    return {
      accepted: false,
      score: maxPlausible,
      reason: 'score_exceeds_questions_ceiling',
      reportedScore,
      maxPlausible,
    };
  }

  // 2) Implausibly fast: a non-trivial score completed faster than a human can
  //    physically answer the questions.
  if (
    timeSpent != null &&
    reportedScore > 0 &&
    timeSpent < questionsAnswered * MIN_SECONDS_PER_QUESTION
  ) {
    return {
      accepted: false,
      score: maxPlausible,
      reason: 'time_too_short_for_questions',
      reportedScore,
      maxPlausible,
    };
  }

  return {
    accepted: true,
    score: reportedScore,
    reason: null,
    reportedScore,
    maxPlausible,
  };
}

module.exports = {
  validateTriviaScore,
  MAX_POINTS_PER_QUESTION,
  MIN_SECONDS_PER_QUESTION,
  GRACE_FACTOR,
};
