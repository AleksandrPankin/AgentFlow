# T-NNN: <короткое название>

<!-- Шаблон Task File. Копирует и заполняет только orchestrator: tasks/T-NNN-slug.md.
     Термины и жизненный цикл: ../docs/ai-handoff-protocol.md (Terms, Task lifecycle).
     Статус задачи живёт в ../state/tasks.md, не здесь. -->

Role: developer | tester | deployer   <!-- ../roles/<role>.md -->
Tool: Claude Code | Codex CLI | Antigravity | Antigravity CLI  <!-- ../roles/tool-routing.md -->
Stage: <номер Stage из docs/project-plan.md>
Depends on: T-xxx | нет
Branch: t-NNN-slug                     <!-- developer; Git rules в протоколе -->
Worktree: <worktrees>\<repo>-t-NNN-slug  <!-- developer; <worktrees> из docs/engineering-rules.md -->
Resume: нет                            <!-- после сбоя: commit SHA | start fresh; см. Recovery в протоколе -->
Checks: T-xxx, commit <SHA>            <!-- tester, deployer; tester without Environment runs in T-xxx's worktree, before merge -->
Environment: staging | prod            <!-- deployer; tester: live check after deploy, from the main folder, no worktree. Pre-merge tester: delete the line -->
Prod approved by human: да (дата) | нет  <!-- deployer -->

## Goal

Одно-два предложения: что должно стать иначе.

## Read first

- файлы, которые нужно прочитать

## Allowed files

- что можно менять (tester, deployer: «ничего»)

## Do not touch

- что нельзя менять

## Environment setup

<!-- Что launcher готовит ДО старта (копия/ссылка): node_modules, dist, venv, .env.example → .env. Исполнитель не собирает это сам. «ничего» — тоже ответ. -->

## Port

<!-- developer/tester, если запускаются сервер или тесты: PORT=<уникальный в этой партии>. Тесты читают его из окружения. -->

## Rebuild together

<!-- deployer и developer общих частей: что нужно пересобрать/выложить вместе с этой задачей и в каком порядке (зависимость → зависимые). «ничего» — тоже ответ. -->

## Review before merge

<!-- нужна ли независимая проверка: нет | tester (интерфейс, в браузере) | чтение дешёвым инструментом. Видимое пользователю или рискованное — не «нет» без записи в decisions.md. -->

## Acceptance criteria

- [ ] проверяемый критерий 1
- [ ] проверяемый критерий 2

## Result

<!-- Заполняет исполнитель. Формат — в его файле роли. -->
