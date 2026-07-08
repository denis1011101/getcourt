# Спека: гости как участники игры (Guest Participants)

## Цель

Владелец игры (или админ) может добавить на страницу игры (`/games/:id`) **гостя** —
незарегистрированного игрока, только по имени, без аккаунта. Аналогично тому, как гости
уже работают при вводе счёта в статистике (`team_a_guests` / `team_b_guests` в
`_stats_match_block`), но теперь гость — полноценный участник:

- отображается в списке Participants с пометкой «(гость)»;
- занимает слот игрока (учитывается в счётчиках участников);
- автоматически подставляется в форму ввода счёта как чекбокс гостя;
- **в Telegram-уведомлениях и списках гость выводится только по имени + «(гость)» —
  никогда не как @ник** (у гостя нет телеграма; не использовать
  `Telegram::Helpers::UserLookup.display_name` для гостей).

Гости НЕ участвуют в ELO — это уже гарантировано существующей логикой
(`PlayerStatistic.build_elo_event` пропускает события с `guest_names_present?`), менять не нужно.

## 1. Миграция БД

Таблица `participations` (сейчас: `user_id NOT NULL`, uniq index `[user_id, game_id]`):

```ruby
class AddGuestNameToParticipations < ActiveRecord::Migration[8.0]
  def change
    add_column :participations, :guest_name, :string
    change_column_null :participations, :user_id, true
  end
end
```

- Существующий уникальный индекс `[user_id, game_id]` оставить: в SQLite NULL-ы в
  уникальном индексе считаются различными, гостей он не ограничивает.
- Дубли гостей ловим валидацией на уровне модели (см. ниже), индекс не обязателен.

## 2. Модель `Participation` (app/models/participation.rb)

```ruby
class Participation < ApplicationRecord
  belongs_to :game
  belongs_to :user, optional: true

  enum :status, { pending: "pending", approved: "approved" }

  validates :user_id, uniqueness: { scope: :game_id, message: "has already joined this game" },
                      allow_nil: true
  validates :status, presence: true
  validates :guest_name, presence: true, length: { maximum: 50 }, if: -> { user_id.blank? }
  validates :guest_name, absence: true, if: -> { user_id.present? }
  validates :guest_name, uniqueness: { scope: :game_id, case_sensitive: false }, allow_blank: true

  scope :guests, -> { where(user_id: nil) }

  def guest?
    user_id.nil?
  end

  # Имя для web-вьюх (без email-фолбэка для гостей)
  def display_name
    guest? ? guest_name : (user.name.presence || user.email)
  end
end
```

Гость всегда создаётся сразу `approved` (его добавляет владелец) — `pending` для гостей не бывает.

## 3. Роут и контроллер

`config/routes.rb` — внутрь существующего `resources :participations`:

```ruby
resources :participations, only: [ :create, :destroy ] do
  # ... существующие approve/reject ...
  collection do
    post :create_guest
  end
end
```

`ParticipationsController`:

- **`create_guest`** — только `can_manage_game?` (владелец или админ), иначе `head :forbidden`.
  Параметр: `params[:guest_name]`. Санитизация как в статистике:
  `params[:guest_name].to_s.strip[0, 50]`; если blank — ошибка.
  Создать `@game.participations.create(guest_name: name, status: "approved", approved_at: Time.current)`.
  Ответ — как в `approve`: turbo_stream replace `participations` (partial `participations/list`)
  + `participation_controls`; html-фолбэк — redirect на игру с notice/alert.
  Ошибку валидации (дубль имени) вернуть alert-ом.

- **`destroy`** — сейчас падает на `AccessControl.can_remove_participant?(current_user, @game, @participation.user)`
  и на `Telegram::ParticipationNotifier.notify_owner(@game, removed_user, ...)` при `user == nil`.
  Изменить:
  - если `@participation.guest?` — разрешать удаление только `can_manage_game?`
    (не звать `AccessControl.can_remove_participant?` с nil);
  - уведомление владельцу: если гостя удалил сам владелец — не слать; если удалил админ —
    слать с именем гостя (см. §6).

## 4. Web-вьюхи

### `app/views/participations/_list.html.erb`
- Approved-список уже включит гостей автоматически (они participations).
- **Не рендерить** `player_statistics/modal` для гостевых participations
  (сейчас строка 11 делает `participation.user.player_statistic` — упадёт на nil).
  Обернуть: `<% if participation.user %> ... modal ... <% end %>`.
- После списка, для `can_manage` — форма добавления гостя:

```erb
<% if can_manage %>
  <%= form_with url: create_guest_game_participations_path(g), method: :post,
        data: { turbo: true }, class: "flex items-center gap-2 mb-4" do %>
    <%= text_field_tag :guest_name, nil, maxlength: 50,
          placeholder: t("games.show.guest_placeholder"),
          class: "w-full rounded border-gray-300 text-sm dark:border-white/15 dark:bg-slate-700 dark:text-slate-100" %>
    <%= submit_tag t("games.show.add_guest"),
          class: "inline-flex items-center rounded-md border border-indigo-300 px-3 py-2 text-sm text-indigo-700 hover:bg-indigo-50 dark:border-white/15 dark:text-slate-100 dark:hover:bg-slate-700/60" %>
  <% end %>
<% end %>
```

### `app/views/participations/_item.html.erb`
Ветка для гостя:
- аватар — первая буква `guest_name`;
- вместо ссылки на модалку статистики — просто текст:
  `<%= participation.display_name %> <span class="text-xs text-gray-500">(<%= t("games.show.guest_badge") %>)</span>`;
- кнопка Remove — для `can_manage?` (владелец/админ); текущий хелпер
  `can_remove_participant?(g, participation.user)` для гостей не звать с nil —
  использовать `can_manage?(g)`.

### Счётчики
`games/show.html.erb:1` (`approved_count`) и предупреждение «Classic format supports up to 4 players»
в `_list` уже считают participations целиком — гости учитываются автоматически, менять не нужно.
Это ожидаемое поведение: гость занимает слот.

## 5. Форма ввода счёта (`app/views/games/_stats_match_block.html.erb` + контроллер)

Гости игры должны появляться в блоках Team A / Team B как чекбоксы (рядом с чекбоксами
зарегистрированных участников):

```erb
<% guest_participations = game.participations.respond_to?(:approved) ?
     game.participations.approved.guests : game.participations.guests %>
<% guest_participations.each do |gp| %>
  <label class="flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
    <%= check_box_tag "matches[#{index}][team_a_guest_names][]", gp.guest_name, false, class: "..." %>
    <span><%= gp.guest_name %> (<%= t("games.show.guest_badge") %>)</span>
  </label>
<% end %>
```

(аналогично для team_b). Свободное текстовое поле `team_a_guests`/`team_b_guests` оставить как есть.

`PlayerStatisticsController`:
- `matches_params` → permit добавить `team_a_guest_names: []`, `team_b_guest_names: []`;
- при сборке: `team_a_guests = sanitize_guest_names([ m[:team_a_guests], *Array(m[:team_a_guest_names]) ])`
  (аналогично для b). `sanitize_guest_names` уже умеет массивы (`Array(value).join(",")`),
  лимит `.first(2)` оставить.

Дальше пайплайн (`MatchUpserter`, `Match#stats["team_*_guest_names"]`, отображение в
`matches_helper`, исключение из ELO) уже работает — не трогать.

## 6. Telegram: гость = имя + «(гость)», без @ника

Правило: для гостевых participations **нигде** не использовать `UserLookup.display_name`.
Формат: `#{guest_name} (#{суффикс})`, суффикс локализованный.

Локали (en/es/ru + телеграм-локали, если они отдельные — проверить `Telegram::I18n`):
- `games.show.guest_badge`: en "guest", es "invitado", ru "гость"
- `games.show.add_guest`: en "Add guest", es "Añadir invitado", ru "Добавить гостя"

Точки правок:

1. **`app/services/telegram/participation_notifier.rb`** — `notify_owner(game, actor, action:)`:
   принять вторым аргументом participation или строку; для гостя:
   `user_name = "#{guest_name} (#{guest_suffix})"` вместо `UserLookup.display_name`.
   Добавить action-тексты `:guest_added` → "was added to your game" (нужен только если
   удалял/добавлял админ, а не сам владелец — владельцу о собственных действиях не слать).

2. **`app/services/telegram/handlers/game_detail_handler.rb:111-130`** — список участников
   игры в боте: сейчас маппит participations в users и рендерит
   `@telegram_username || name || email`. Добавить гостей: для `participation.guest?`
   выводить `guest_name (гость)`; в счётчик участников (строки 16-17) гости уже входят.

3. **`app/services/telegram/flows/games/participants_manage_flow.rb`** — управление
   участниками из бота: `participants = game.participations.map(&:user).compact` теряет
   гостей. Показать гостей с пометкой «(гость)»; кнопка удаления гостя — по
   `participation.id` (не `user_id`). Если правка потока громоздкая — минимум: гости
   отображаются в списке, удаление гостя допустимо оставить только в вебе (пометить TODO).

4. **`app/services/telegram/helpers/game_card_renderer.rb:116-117`** — счётчик participations
   уже включает гостей, менять не нужно.

## 7. Смежное поведение (проверить, но не ломать)

- **`ResetParticipationsJob`** — `game.participations.delete_all` удалит и гостей при
  еженедельном сбросе recurring-игры. Это ок и консистентно с обычными участниками.
- **`allowed_to_fill_stats?`** и прочие `exists?(user_id: ...)` — не затрагиваются
  (у гостей `user_id NULL`, в выборки по user_id они не попадают).
- Везде, где есть `participations.map(&:user)` — проверить на nil
  (`game_participants` в `PlayerStatisticsController`, `increment_activity_for_game!` —
  там уже `.compact`, ок; `participants_manage_flow` — см. §6.3;
  `_stats_match_block` строка 5 `scope.includes(:user).map(&:user)` + `.compact` уже есть в строке 7).

## 8. Тесты (minitest, test/)

- Модель: гость валиден без user; нельзя одновременно user и guest_name; дубль
  guest_name в одной игре (case-insensitive) невалиден; лимит 50 символов.
- Контроллер `create_guest`: владелец — 200/redirect, участник появился approved;
  не-владелец — forbidden; пустое имя — alert.
- Контроллер `destroy`: владелец удаляет гостя; чужой пользователь — forbidden;
  для гостя не вызывается notifier с nil-user (нет исключения).
- Страница игры: гость в списке с «(гость)», модалка статистики не рендерится, счётчик слотов растёт.
- `PlayerStatisticsController#create`: чекбоксы `team_a_guest_names[]` мержатся с текстовым
  полем, матч создаётся с `stats["team_a_guest_names"]`, ELO не пересчитывается для события с гостями.
- `ParticipationNotifier`: текст для гостя содержит имя и «(гость)», не содержит `@`.
