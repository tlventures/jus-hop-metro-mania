'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  validateTriviaScore,
  MAX_POINTS_PER_QUESTION,
} = require('../lib/anti-cheat');

test('accepts a plausible score within the per-question ceiling', () => {
  const v = validateTriviaScore({ score: 300, questionsAnswered: 10, timeSpent: 60 });
  assert.equal(v.accepted, true);
  assert.equal(v.score, 300);
  assert.equal(v.reason, null);
});

test('clamps a score that exceeds the questions ceiling', () => {
  const v = validateTriviaScore({ score: 100000, questionsAnswered: 10 });
  assert.equal(v.accepted, false);
  assert.equal(v.reason, 'score_exceeds_questions_ceiling');
  // 10 questions * 30 * 1.05 grace = 315.
  assert.equal(v.score, 315);
  assert.equal(v.reportedScore, 100000);
});

test('clamps when the game finished implausibly fast', () => {
  const v = validateTriviaScore({ score: 200, questionsAnswered: 10, timeSpent: 2 });
  assert.equal(v.accepted, false);
  assert.equal(v.reason, 'time_too_short_for_questions');
});

test('accepts (cannot bound) when questionsAnswered is unknown', () => {
  const v = validateTriviaScore({ score: 5000, questionsAnswered: 0 });
  assert.equal(v.accepted, true);
  assert.equal(v.maxPlausible, null);
});

test('the per-question ceiling constant is the agreed 30', () => {
  assert.equal(MAX_POINTS_PER_QUESTION, 30);
});

test('a score exactly at the grace ceiling is accepted', () => {
  const v = validateTriviaScore({ score: 315, questionsAnswered: 10 });
  assert.equal(v.accepted, true);
});
