# Tutor quiz cards

Artifact-Version: 1
Status: Implemented

## Intent
Self-testing is the most effective way to study a lecture. Like NotebookLM's quizzes, the assistant should generate practice questions grounded in the lecture's transcript, slides, courseware and notes, and the student should answer them in a focused card view and review mistakes.

Outcome: a new assistant write target, quiz sets, with a chat card and a full-screen practice view, and scores feeding the activity heatmap.

This widens the assistant's write boundary (today: notes, schedule marks, outlines) to include quiz sets; nothing else changes about what the assistant may write.

Non-goals (first version): flashcards, free-text answers graded by a model, sharing quiz sets, spaced repetition.

## Contract

### Quiz set
`{id, title, course_id, lecture_id?, difficulty: easy|medium|hard, created_at, source: agent|user, questions:[{id, stem, options:[{text, rationale}], answer, hint?, topic?, ref?}]}`
- `stem`, option text and rationale are Markdown with LaTeX (rendered by `LookMarkdown`).
- 2–6 options, exactly one correct `answer` index, 1–30 questions; `ref` is a `look://` link (timestamp, slide or courseware) pointing at the evidence.
- Size limits (characters): stem 1000, option 300, rationale 1000, hint 500, topic 40, ref 500; the questions serialized at most 256 KB; a library holds at most 2000 sets (a new set beyond that is refused with a message, rewriting an existing set is not).
- lookd validates and stores the set in table `quizzes` and mirrors it, with its attempts, to `<library>/quizzes/<id>.json` (restored by reindex: the file's attempts replace the set's attempts in the index, and only attempts that belong to the set, have one valid answer per question and match a regrade are imported); saving a set, recording an attempt and deleting a set each change the index and the file in one transaction with the activity mirror's journal and lock ([spec 0001](0001-learning-activity-heatmap.md)): if the file cannot be written or removed nothing changes, and if the index does not commit (a failed commit or a crash) the previous file is restored; an attempt checks inside its transaction that the set still exists, so it cannot bring a deleted set back; a set and its attempts are deleted together; attempts go to `quiz_attempts(id, quiz_id, started_at, finished_at, answers, correct, total)`. lookd grades attempts itself from the submitted option indexes (`-1` = skipped).
- A set keeps at most 50 attempts: its newest 49 and its best (by score, then newest); older ones are dropped when an attempt is recorded and when a file copy is restored, so the mirror rewrite stays bounded. Dropped attempts also leave the heatmap's per-day `quizzes` counts.
- Validation: options are unique and non-empty, stems unique within a set; sets with `source: agent` need a `look://` `ref` per question and a rationale per option (user sets need neither). A `lecture_id` must exist and sets the course.
- API: `POST /api/quizzes`, `GET /api/quizzes?lecture_id|course_id` (without questions; the list selects metadata only and SQLite counts the questions, so they are never decoded), `GET /api/quizzes/{id}` (with best score and the last attempt's answers), `DELETE /api/quizzes/{id}` (with its attempts), `POST /api/quizzes/{id}/attempts {started_at, answers}` → `{attempt, best}`. Changes publish `quizzes_changed`; attempts also `activity_changed`.
- Finished attempts count in the activity heatmap as `quizzes` per day (derived from `quiz_attempts`, like notes) and appear in the day sheet with their score; practice time is the `practice` kind.

### Assistant
- New tool group `practice` loaded through `find_tools`: `create_quiz` (saves a set), `list_quizzes`, `read_quiz_results` (scores and the questions the student missed).
- The tool description and a playbook (returned by `find_tools`, like the notes playbook) require reading the source material first, one fact per question, plausible distractors, a rationale for every option, and a `ref` for every question.
- `create_quiz` refuses a set when: the whole-lecture transcript was not read in this conversation (more than 10% unread, as for notes; `partial: true` for a part of the lecture or a lecture without transcript); a `ref` is not a valid `look://` link to the same lecture; a timestamp `ref` lies outside the transcript spans read (±90 s); or with 4+ questions every answer is at the same position.
- The tool result renders in chat as a quiz card.

### UI
- Chat quiz card: title, lecture, `10 题 · 中等`, best score if taken, primary button 开始练习.
- Player side panel: 出题练习… in the transcript menu (next to 让助手整理笔记) and a 练习 section under the notes tab listing the lecture's sets with an 出题 button; both open a sheet with 题量 5 / 10 / 15, 难度 简单 / 中等 / 困难, and an optional 侧重 text field; it sends a templated request to the assistant.
- Practice view (full screen, max content width 720 dp):
  - top: close, title, `3 / 10` and a linear progress indicator;
  - question card: stem, options as full-width outlined option rows with letter badges, 提示 text button revealing the hint;
  - after selecting: the chosen row turns error or primary container with an icon, the correct row is marked, each option shows its rationale; buttons 讲解 (asks the assistant to explain this question with the student's choice, shown in an assistant sheet over the practice view) and 查看出处 (opens the `ref` in the player or reader);
  - keyboard: 1–6 select, Enter next, ←/→ navigate;
  - finish screen: score, time, best score, a per-topic list of right and wrong, a per-question review list, actions 重做错题 (a retake of only those questions, not recorded as an attempt), 再出一组（针对错题）, 完成.
- Library 资料库 shows a 练习 section with all sets (best score, attempts) between notes and the library card.
- Visual rules as in the usage spec: tonal containers, theme roles for right/wrong (primary and error, always with an icon and text), no confetti or decorative animation; motion is a short shared-axis transition between questions.

## Plan
1. lookd: tables, validation, handlers, file mirror, activity hook, tests.
2. Agent: `practice` tool group, guidance text, result `details` for the card.
3. App: `features/practice/` (card, sheet, practice view, finish screen), library listing, activity tracker hook and heatmap counts.

## Verification
- `go test`: validation rejects bad answer indexes, option counts and missing refs; attempts update best score; file mirror written; attempts capped at 50 keeping the best.
- Agent: `node --test` for `create_quiz` argument checks.
- `flutter test`: answering flow (select, reveal, next, finish score) on a fixture set.
- Live: ask the assistant for 5 medium questions on a transcribed lecture; every question has a working source link; the attempt appears in the heatmap day sheet.

## Evidence
- Store: [quiz.go](../../lookd/internal/store/quiz.go) with [quiz_test.go](../../lookd/internal/store/quiz_test.go) (validation cases including size limits, grading, a list that skips the questions, the set cap, best and last scores, activity counts and day detail, delete with attempts); mirror [library/quiz.go](../../lookd/internal/library/quiz.go) with [quiz_test.go](../../lookd/internal/library/quiz_test.go) (unknown lecture, restore by reindex, invalid attempts skipped on reindex, attempts replaced by the file's on reindex, file removed on delete, set kept when the file cannot be removed, set and attempt not kept when the file write fails, an attempt on a deleted set refused, an interrupted delete restored on open); [quiz_mirror_test.go](../../lookd/internal/store/quiz_mirror_test.go) (a failed commit keeps the set and its attempts and restores the file); handlers [server/quiz.go](../../lookd/internal/server/quiz.go).
- Agent: [practice.mjs](../../agent/src/practice.mjs) (ref parsing including malformed escapes, grounding checks, playbook) with [practice.test.mjs](../../agent/src/practice.test.mjs); tools `create_quiz`, `list_quizzes`, `read_quiz_results` in [tools.mjs](../../agent/src/tools.mjs); system prompt in [host.mjs](../../agent/src/host.mjs).
- App: [quiz.dart](../../app/lib/features/practice/quiz.dart) (models, card, list, generation sheet, assistant sheet), [practice_page.dart](../../app/lib/features/practice/practice_page.dart); [practice_test.dart](../../app/test/practice_test.dart) drives hint, wrong and right answers (tap and keyboard), the recorded answers, the summary and an unrecorded retake.
- Live check (2026-10-14, lookd API): an agent set without `ref` was rejected with the question number; a valid set got the course and lecture title and wrote `quizzes/<id>.json`; a wrong-length attempt returned 400; a correct attempt returned the best score and showed in today's activity day; deleting removed the rows, the file and the day's count.
- Not verified: an end-to-end generation by a live model (it spends the user's tokens; the grounding checks are unit-tested) and the visual design.
