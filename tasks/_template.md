# T-NNN: <короткое название>

<!-- Шаблон Task File. Копирует и заполняет только orchestrator: tasks/T-NNN-slug.md.
     Термины и жизненный цикл: ../docs/ai-handoff-protocol.md (Terms, Task lifecycle).
     Статус задачи живёт в ../state/tasks.md, не здесь. -->

Role: developer | tester | deployer   <!-- ../roles/<role>.md -->
Tool: Claude Code | Codex CLI | Antigravity | Antigravity CLI  <!-- ../roles/tool-routing.md -->
Stage: <номер Stage из docs/project-plan.md>
Depends on: T-xxx | нет
Branch: t-NNN-slug                     <!-- developer; Git rules в протоколе -->
Worktree: <worktrees>\<repo>-t-NNN-slug  <!-- developer; <worktrees> из Project rules (протокол, Terms) -->
Resume: нет                            <!-- после сбоя: commit SHA | start fresh; см. Recovery в протоколе -->
Verifies: T-xxx @ <SHA>                <!-- tester: проверяемая задача и commit -->
Deploys: <SHA>                         <!-- deployer -->
Target: staging | prod                 <!-- deployer; tester после выкладки. Проверка до merge (local): удалить строку -->
Independent check: tester | none - <причина>  <!-- developer: tester, если видно пользователю или рискованно; см. Acceptance в протоколе -->

## Goal

Одно-два предложения: что должно стать иначе.

## Read first

- файлы, которые нужно прочитать

## Allowed files

<!-- Тесты, которые проверяют меняемое поведение, — тоже сюда: старый тест, противоречащий новой задаче, в Do not touch = гарантированный blocked. Пересечение с Do not touch и с незавершёнными задачами run-task.ps1 не пропустит. -->

- что можно менять (tester, deployer: «ничего»)

## Do not touch

- что нельзя менять

## Setup

<!-- Что launcher готовит ДО старта (копия/ссылка): node_modules, dist, venv, .env.example → .env. Исполнитель не собирает это сам. «ничего» — тоже ответ. -->

## Port

<!-- developer/tester, если запускаются сервер или тесты: PORT=<уникальный в этой партии>. Тесты читают его из окружения. -->

## Rebuild together

<!-- deployer и developer общих частей: что нужно пересобрать/выложить вместе с этой задачей и в каком порядке (зависимость → зависимые). «ничего» — тоже ответ. -->

## Acceptance criteria

- [ ] проверяемый критерий 1
- [ ] проверяемый критерий 2

## Checks

<!-- Точные команды, которые доказывают критерии. Исполнитель запускает их дословно, приёмка — те же команды.
     Узко: конкретный spec-файл или фильтр, а не весь набор. Только локальное окружение (AGENTFLOW_TARGET=local). Запускаются в PowerShell (Windows) или sh.
     Проверки без команды (скриншот, ручной шаг) — отдельной строкой без обратных кавычек.
     Проектные запреты и обязательные флаги — секция "## Preflight" в Project rules; run-task.ps1 проверяет их до запуска. -->

- `<команда>` — какой критерий доказывает

## Result

<!-- Заполняет исполнитель. Формат — в его файле роли. -->
