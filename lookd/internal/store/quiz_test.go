package store

import (
	"context"
	"strings"
	"testing"
)

func agentQuiz() Quiz {
	opt := func(t string) QuizOption { return QuizOption{Text: t, Rationale: "因为" + t} }
	return Quiz{Title: "傅里叶变换自测", Source: "agent", LectureID: "l1", CourseID: "c1", Questions: []QuizQuestion{
		{Stem: "矩形脉冲的频谱是？", Options: []QuizOption{opt("sinc 函数"), opt("冲激"), opt("常数")}, Answer: 0, Ref: "look://lecture/l1?t=120"},
		{Stem: "时域卷积对应频域？", Options: []QuizOption{opt("相乘"), opt("相加")}, Answer: 0, Ref: "look://slide/l1/3"},
	}}
}

func TestValidateQuiz(t *testing.T) {
	q := agentQuiz()
	if err := ValidateQuiz(&q); err != nil {
		t.Fatal(err)
	}
	if q.Difficulty != "medium" || q.Questions[1].ID != "q2" || q.Count != 2 {
		t.Fatalf("defaults not filled: %+v", q)
	}
	cases := map[string]func(*Quiz){
		"answer 应为":    func(q *Quiz) { q.Questions[0].Answer = 3 },
		"2–6 个选项":      func(q *Quiz) { q.Questions[1].Options = q.Questions[1].Options[:1] },
		"缺少出处 ref":     func(q *Quiz) { q.Questions[1].Ref = "" },
		"缺少 rationale": func(q *Quiz) { q.Questions[0].Options[2].Rationale = " " },
		"不能为空或重复":      func(q *Quiz) { q.Questions[0].Options[1].Text = "SINC 函数" },
		"重复":           func(q *Quiz) { q.Questions[1].Stem = q.Questions[0].Stem },
		"difficulty":   func(q *Quiz) { q.Difficulty = "extreme" },
		"题目数量":         func(q *Quiz) { q.Questions = nil },
	}
	for want, breakIt := range cases {
		q := agentQuiz()
		breakIt(&q)
		if err := ValidateQuiz(&q); err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("%s: got %v", want, err)
		}
	}
	// Users may write sets without sources or explanations.
	u := agentQuiz()
	u.Source = "user"
	u.Questions[0].Ref, u.Questions[0].Options[0].Rationale = "", ""
	if err := ValidateQuiz(&u); err != nil {
		t.Fatalf("user set rejected: %v", err)
	}
}

func TestQuizAttemptsAndActivity(t *testing.T) {
	ctx := context.Background()
	s := openTemp(t)
	q := agentQuiz()
	q.ID, q.CreatedAt = "z1", at("2026-10-01", 9)
	if err := ValidateQuiz(&q); err != nil {
		t.Fatal(err)
	}
	if err := s.PutQuiz(ctx, q); err != nil {
		t.Fatal(err)
	}
	if _, err := Grade(q, []int{0}); err == nil {
		t.Fatal("short answers accepted")
	}
	if _, err := Grade(q, []int{0, 5}); err == nil {
		t.Fatal("out-of-range answer accepted")
	}
	for i, a := range []struct {
		answers []int
		day     string
	}{{[]int{0, 1}, "2026-10-01"}, {[]int{0, 0}, "2026-10-02"}, {[]int{-1, 1}, "2026-10-02"}} {
		c, err := Grade(q, a.answers)
		if err != nil {
			t.Fatal(err)
		}
		ts := at(a.day, 10+i)
		if err := s.PutQuizAttempt(ctx, QuizAttempt{ID: string(rune('a' + i)), QuizID: "z1", StartedAt: ts - 60, FinishedAt: ts, Answers: a.answers, Correct: c, Total: 2}); err != nil {
			t.Fatal(err)
		}
	}
	got, err := s.Quiz(ctx, "z1")
	if err != nil {
		t.Fatal(err)
	}
	if got.Attempts != 3 || got.Best.Correct != 2 || got.Last.Correct != 0 || len(got.Last.Answers) != 2 || got.Last.Answers[0] != -1 {
		t.Fatalf("scores: attempts %d best %+v last %+v", got.Attempts, got.Best, got.Last)
	}
	list, _ := s.Quizzes(ctx, "c1", "")
	if len(list) != 1 || list[0].Questions != nil || list[0].Count != 2 || list[0].Last.Answers != nil {
		t.Fatalf("list = %+v", list)
	}

	days, err := s.ActivityDays(ctx, "2026-10-01", "2026-10-03", "")
	if err != nil {
		t.Fatal(err)
	}
	if days[0].Quizzes != 1 || days[1].Quizzes != 2 || !days[1].Active() || days[2].Active() {
		t.Fatalf("days = %+v", days)
	}
	d, err := s.ActivityOn(ctx, "2026-10-02")
	if err != nil {
		t.Fatal(err)
	}
	if len(d.Attempts) != 2 || d.Attempts[0].Correct != 2 || d.Attempts[0].Title != q.Title {
		t.Fatalf("detail attempts = %+v", d.Attempts)
	}

	if err := s.DeleteQuiz(ctx, "z1"); err != nil {
		t.Fatal(err)
	}
	if a, _ := s.QuizAttempts(ctx, "z1"); len(a) != 0 {
		t.Fatal("attempts kept after delete")
	}
	if err := s.DeleteQuiz(ctx, "z1"); err == nil {
		t.Fatal("deleting a missing quiz succeeded")
	}
}
