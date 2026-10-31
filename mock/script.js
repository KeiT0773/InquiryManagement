/* ============================================================
   問い合わせ管理ボード モック
   - TaskManagement のカンバンボードと同じ構造（3リスト＋詳細モーダル＋ドラッグ&ドロップ）
   - リスト＝ステータス（未対応 / 対応中 / 完了）
   - データはメモリ上にのみ保持する（サーバー保存はモック対象外）
   - 画面イメージと操作感の認識合わせを目的とする
   ============================================================ */

// ---------- 定数 ----------
const LISTS = [
  { id: 'open',    name: '未対応' },
  { id: 'working', name: '対応中' },
  { id: 'closed',  name: '完了' },
];

const PRIORITY_LABEL = { high: '高', medium: '中', low: '低' };
const PRIORITY_ORDER = { high: 0, medium: 1, low: 2 }; // 並べ替え時の順序（小さいほど上）

const CATEGORY_LABEL = { question: '質問', bug: '不具合', request: '要望', other: 'その他' };

// ---------- サンプルデータ ----------
// 日付は「今日から何日後か」で持たせ、いつ開いても期限切れの例が見えるようにする
function dateFromToday(offsetDays) {
  const d = new Date();
  d.setDate(d.getDate() + offsetDays);
  return toDateString(d);
}

let inquiries = [
  { id: 1, listId: 'open',    title: 'ログインできない',             customer: '山田 太郎',   contact: 'yamada@example.com',   category: 'bug',      assignee: '',       description: 'パスワードを再設定してもログイン画面に戻される。', memo: '',                               received: dateFromToday(-1), due: dateFromToday(1),  priority: 'high' },
  { id: 2, listId: 'open',    title: '請求書の再発行について',       customer: '佐藤 花子',   contact: '03-1234-5678',         category: 'question', assignee: '小林',   description: '先月分の請求書を紛失したため再発行してほしい。', memo: '',                               received: dateFromToday(-4), due: dateFromToday(-1), priority: 'medium' },
  { id: 3, listId: 'open',    title: 'CSV出力に項目を追加してほしい', customer: '鈴木 一郎',   contact: 'suzuki@example.com',   category: 'request',  assignee: '',       description: '問い合わせ一覧の CSV に受付日を含めてほしい。',  memo: '',                               received: dateFromToday(0),  due: '',                priority: 'low' },
  { id: 4, listId: 'working', title: 'プラン変更の手続き',           customer: '高橋 美咲',   contact: 'takahashi@example.com', category: 'question', assignee: '小林',   description: '年契約から月契約に切り替えたい。',               memo: '契約担当に確認中。',             received: dateFromToday(-3), due: dateFromToday(3),  priority: 'medium' },
  { id: 5, listId: 'working', title: '画面が真っ白になる',           customer: '田中 健',     contact: 'tanaka@example.com',   category: 'bug',      assignee: '中村',   description: 'Safari で一覧画面を開くと何も表示されない。',     memo: '再現手順を開発チームに共有済み。', received: dateFromToday(-2), due: dateFromToday(0),  priority: 'high' },
  { id: 8, listId: 'working', title: '領収書の宛名を変更したい',     customer: '小川 直子',   contact: 'ogawa@example.com',    category: 'question', assignee: '中村',   description: '領収書の宛名を会社名に変更して再発行してほしい。', memo: '経理に確認中。',                 received: dateFromToday(-2), due: dateFromToday(1),  priority: 'medium' },
  { id: 6, listId: 'closed',  title: '営業時間の確認',               customer: '伊藤 さくら', contact: '090-0000-1111',        category: 'other',    assignee: '中村',   description: '電話窓口の営業時間を教えてほしい。',             memo: '平日 9:00〜18:00 と回答。',      received: dateFromToday(-6), due: '',                priority: 'low' },
  { id: 7, listId: 'closed',  title: '退会方法を知りたい',           customer: '渡辺 誠',     contact: 'watanabe@example.com', category: 'question', assignee: '小林',   description: 'アカウントの退会手順が分からない。',             memo: 'ヘルプページの URL を案内。',    received: dateFromToday(-5), due: dateFromToday(-3), priority: 'medium' },
];

// 問い合わせを登録できるのは「未対応」だけ（新しい問い合わせは必ず未対応から始まる）
const REGISTER_LIST_ID = 'open';
// 「対応中」はあえて並べ替えの規則どおりになっていない（中が高より上、同じ中の中で期限の遠い方が上）。
// ツールバーの「優先度順に並べ替え」を押すと変化が分かる。

let nextId = 9;

// ---------- 日付ユーティリティ ----------
function toDateString(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function today() {
  return toDateString(new Date());
}

// 表示用 "MM/DD"
function formatDate(date) {
  const [, m, d] = date.split('-');
  return `${m}/${d}`;
}

// 期限切れ判定：対応期限が今日より前、かつ「完了」以外のステータスにある
function isOverdue(inquiry) {
  return inquiry.due !== '' && inquiry.due < today() && inquiry.listId !== 'closed';
}

// ---------- 優先度順の並べ替え（機能要件書 3.1） ----------
// 並び順の比較：優先度（高→中→低）→ 対応期限の近い順。対応期限が未設定のものは同じ優先度の最後。
// 対応期限は "YYYY-MM-DD" の文字列なので、文字列の比較で日付の前後が分かる（期限切れは日付が早いため上）。
function compareForSort(a, b) {
  const byPriority = PRIORITY_ORDER[a.priority] - PRIORITY_ORDER[b.priority];
  if (byPriority !== 0) return byPriority;
  if (a.due === b.due) return 0; // 未設定どうしも含む
  if (a.due === '') return 1;
  if (b.due === '') return -1;
  return a.due < b.due ? -1 : 1;
}

// 指定リストの問い合わせを compareForSort の順に並べ直す。
// 優先度も対応期限も同じものどうしは元の順序を保つ（Array.sort は安定ソート）ため、
// 末尾に置いてから呼べば「優先度も対応期限も同じまとまりの末尾」に入る。
function sortListByPriority(listId) {
  const target = inquiries.filter((q) => q.listId === listId);
  const rest = inquiries.filter((q) => q.listId !== listId);
  target.sort(compareForSort);
  inquiries = [...rest, ...target];
}

// 全リストを優先度順に並べ直す。優先度も対応期限も同じものの順序は sortListByPriority が保つ。
function sortAllByPriority() {
  LISTS.forEach((list) => sortListByPriority(list.id));
}

// ---------- ボード描画 ----------
const boardEl = document.getElementById('board');

function renderBoard() {
  boardEl.innerHTML = '';

  LISTS.forEach((list) => {
    const listInquiries = inquiries.filter((q) => q.listId === list.id);

    const listEl = document.createElement('section');
    listEl.className = 'list';
    listEl.dataset.listId = list.id;

    // リスト見出し
    const header = document.createElement('div');
    header.className = 'list-header';
    header.innerHTML = `<span>${list.name}</span><span class="list-count">${listInquiries.length}件</span>`;
    listEl.appendChild(header);

    // 問い合わせ一覧
    const container = document.createElement('div');
    container.className = 'card-container';
    container.dataset.listId = list.id;
    listInquiries.forEach((inquiry) => container.appendChild(createCardElement(inquiry)));
    setupDropZone(container);
    listEl.appendChild(container);

    // 問い合わせ登録（未対応のリストだけ）
    if (list.id === REGISTER_LIST_ID) {
      const addArea = document.createElement('div');
      addArea.className = 'add-area';
      renderAddButton(addArea, list.id);
      listEl.appendChild(addArea);
    }

    boardEl.appendChild(listEl);
  });
}

function createCardElement(inquiry) {
  const el = document.createElement('div');
  el.className = 'card';
  el.draggable = true;
  el.dataset.cardId = inquiry.id;

  const overdue = isOverdue(inquiry);
  const dueText = inquiry.due === ''
    ? ''
    : `期限 ${formatDate(inquiry.due)}${overdue ? '（期限切れ）' : ''}`;

  el.innerHTML = `
    <div class="card-title-row">
      <span class="badge badge-${inquiry.priority}">${PRIORITY_LABEL[inquiry.priority]}</span>
      <span class="card-title"></span>
    </div>
    <div class="card-people">
      <span class="card-customer"></span>
      <span class="card-assignee"></span>
    </div>
    <div class="card-meta">
      <span class="category category-${inquiry.category}">${CATEGORY_LABEL[inquiry.category]}</span>
      <span class="card-due ${overdue ? 'overdue' : ''}">${dueText}</span>
    </div>
  `;
  // ユーザー入力値は textContent で入れる（HTML として解釈させない）
  el.querySelector('.card-title').textContent = inquiry.title;
  el.querySelector('.card-customer').textContent = inquiry.customer === '' ? '' : `${inquiry.customer} 様`;
  const assigneeEl = el.querySelector('.card-assignee');
  assigneeEl.textContent = inquiry.assignee === '' ? '対応者 未割当' : `対応者 ${inquiry.assignee}`;
  assigneeEl.classList.toggle('unassigned', inquiry.assignee === '');

  el.addEventListener('click', () => openDetail(inquiry.id));
  el.addEventListener('dragstart', onDragStart);
  el.addEventListener('dragend', onDragEnd);

  return el;
}

// ---------- 問い合わせ登録 ----------
function renderAddButton(addArea, listId) {
  addArea.innerHTML = '';
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'btn-add';
  btn.textContent = '＋ 問い合わせを登録';
  btn.addEventListener('click', () => renderAddForm(addArea, listId));
  addArea.appendChild(btn);
}

function renderAddForm(addArea, listId) {
  const radioName = `add-priority-${listId}`;
  addArea.innerHTML = `
    <form class="add-form">
      <input type="text" class="input-title" placeholder="件名を入力（必須）" maxlength="100">
      <input type="text" class="input-sub input-customer" placeholder="問い合わせ者（必須）" maxlength="50">
      <textarea class="input-description" rows="3" placeholder="問い合わせ内容（必須）"></textarea>
      <select class="input-sub input-category">
        <option value="question">質問</option>
        <option value="bug">不具合</option>
        <option value="request">要望</option>
        <option value="other">その他</option>
      </select>
      <div class="priority-options priority-options-compact">
        <label><input type="radio" name="${radioName}" value="high"> <span class="badge badge-high">高</span></label>
        <label><input type="radio" name="${radioName}" value="medium" checked> <span class="badge badge-medium">中</span></label>
        <label><input type="radio" name="${radioName}" value="low"> <span class="badge badge-low">低</span></label>
      </div>
      <p class="form-error" role="alert"></p>
      <div class="add-form-buttons">
        <button type="submit" class="btn-primary">登録</button>
        <button type="button" class="btn-secondary btn-cancel">キャンセル</button>
      </div>
    </form>
  `;
  const form = addArea.querySelector('form');
  const titleEl = form.querySelector('.input-title');
  const customerEl = form.querySelector('.input-customer');
  const descriptionEl = form.querySelector('.input-description');
  const errorEl = form.querySelector('.form-error');
  titleEl.focus();

  // 必須項目：件名・問い合わせ者・問い合わせ内容（空白だけの入力も未入力とみなす）
  const requiredFields = [
    { el: titleEl,       label: '件名' },
    { el: customerEl,    label: '問い合わせ者' },
    { el: descriptionEl, label: '問い合わせ内容' },
  ];

  // 入力し直したらその欄のエラー表示を消す
  requiredFields.forEach(({ el }) => {
    el.addEventListener('input', () => el.classList.remove('input-error'));
  });

  form.addEventListener('submit', (e) => {
    e.preventDefault();
    const missing = requiredFields.filter(({ el }) => el.value.trim() === '');
    requiredFields.forEach(({ el }) => el.classList.toggle('input-error', missing.some((m) => m.el === el)));
    if (missing.length > 0) {
      // 必須項目が空のときは登録せず、最初の未入力欄にフォーカスする
      errorEl.textContent = `${missing.map((m) => m.label).join('・')}を入力してください`;
      missing[0].el.focus();
      return;
    }
    const priority = form.querySelector(`input[name="${radioName}"]:checked`).value;
    inquiries.push({
      id: nextId++,
      listId,
      title: titleEl.value.trim(),
      customer: customerEl.value.trim(),
      contact: '',
      category: form.querySelector('.input-category').value,
      assignee: '', // 対応者は詳細画面で設定する
      description: descriptionEl.value.trim(),
      memo: '',
      received: today(), // 受付日は登録日で自動設定
      due: '',
      priority, // 初期値は「中」（フォームで変更可）
    });
    sortListByPriority(listId); // 登録後はリスト全体を優先度順に並べ直す
    renderBoard();
    // 続けて登録できるよう、同じリストの入力欄を開いたままにする
    const newAddArea = boardEl.querySelector(`.list[data-list-id="${listId}"] .add-area`);
    renderAddForm(newAddArea, listId);
  });

  form.querySelector('.btn-cancel').addEventListener('click', () => renderAddButton(addArea, listId));
  form.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') renderAddButton(addArea, listId);
  });
}

// ---------- ドラッグ&ドロップ（ステータス変更・並べ替え） ----------
let draggingCardId = null;
let placeholderEl = null;

function onDragStart(e) {
  draggingCardId = Number(e.currentTarget.dataset.cardId);
  e.currentTarget.classList.add('dragging');
  e.dataTransfer.effectAllowed = 'move';

  placeholderEl = document.createElement('div');
  placeholderEl.className = 'placeholder';
}

function onDragEnd() {
  document.querySelectorAll('.card.dragging').forEach((el) => el.classList.remove('dragging'));
  if (placeholderEl && placeholderEl.parentNode) placeholderEl.remove();
  placeholderEl = null;
  draggingCardId = null;
}

function setupDropZone(container) {
  container.addEventListener('dragover', (e) => {
    e.preventDefault(); // ドロップを許可
    if (!placeholderEl) return;

    // マウス位置より下にある最初のカードの前にプレースホルダーを入れる
    const cardEls = [...container.querySelectorAll('.card:not(.dragging)')];
    const nextCard = cardEls.find((el) => {
      const rect = el.getBoundingClientRect();
      return e.clientY < rect.top + rect.height / 2;
    });
    if (nextCard) {
      container.insertBefore(placeholderEl, nextCard);
    } else {
      container.appendChild(placeholderEl);
    }
  });

  container.addEventListener('drop', (e) => {
    e.preventDefault();
    if (draggingCardId === null || !placeholderEl) return;

    const targetListId = container.dataset.listId;
    // プレースホルダーの位置＝挿入先インデックス（ドラッグ中カードは除外して数える）
    const siblings = [...container.children].filter((el) => !el.classList.contains('dragging'));
    const insertIndex = siblings.indexOf(placeholderEl);

    moveInquiry(draggingCardId, targetListId, insertIndex);
    onDragEnd();
    renderBoard();
  });
}

// 指定したステータスの指定位置へ移す（insertIndex 省略時は末尾）
function moveInquiry(inquiryId, targetListId, insertIndex) {
  const inquiry = inquiries.find((q) => q.id === inquiryId);
  const others = inquiries.filter((q) => q.id !== inquiryId);

  const targetInquiries = others.filter((q) => q.listId === targetListId);
  const restInquiries = others.filter((q) => q.listId !== targetListId);

  inquiry.listId = targetListId;
  targetInquiries.splice(insertIndex ?? targetInquiries.length, 0, inquiry);

  inquiries = [...restInquiries, ...targetInquiries];
}

// ---------- 問い合わせ詳細（SC-02） ----------
const overlayEl = document.getElementById('modal-overlay');
const titleInput = document.getElementById('detail-title');
const customerInput = document.getElementById('detail-customer');
const contactInput = document.getElementById('detail-contact');
const categorySelect = document.getElementById('detail-category');
const statusSelect = document.getElementById('detail-status');
const dueInput = document.getElementById('detail-due');
const assigneeInput = document.getElementById('detail-assignee');
const descInput = document.getElementById('detail-description');
const memoInput = document.getElementById('detail-memo');
const receivedEl = document.getElementById('detail-received');
const priorityRadios = document.querySelectorAll('input[name="priority"]');
let editingId = null;

// ステータスの選択肢は LISTS から作る（ボードの列と常に一致させる）
LISTS.forEach((list) => {
  const option = document.createElement('option');
  option.value = list.id;
  option.textContent = list.name;
  statusSelect.appendChild(option);
});

function openDetail(inquiryId) {
  const inquiry = inquiries.find((q) => q.id === inquiryId);
  if (!inquiry) return;
  editingId = inquiryId;

  titleInput.value = inquiry.title;
  customerInput.value = inquiry.customer;
  contactInput.value = inquiry.contact;
  categorySelect.value = inquiry.category;
  statusSelect.value = inquiry.listId;
  dueInput.value = inquiry.due;
  assigneeInput.value = inquiry.assignee;
  descInput.value = inquiry.description;
  memoInput.value = inquiry.memo;
  receivedEl.textContent = `受付日 ${inquiry.received.replaceAll('-', '/')}`;
  priorityRadios.forEach((r) => { r.checked = r.value === inquiry.priority; });

  overlayEl.hidden = false;
  titleInput.focus();
}

function closeDetail() {
  overlayEl.hidden = true;
  editingId = null;
}

function findEditing() {
  return inquiries.find((q) => q.id === editingId);
}

// 入力のたびに即時反映（閉じる前に保存済みという要件を表現）
function updateEditing(changes) {
  const inquiry = findEditing();
  if (!inquiry) return;
  Object.assign(inquiry, changes);
  renderBoard();
}

titleInput.addEventListener('input', () => {
  const title = titleInput.value.trim();
  if (title !== '') updateEditing({ title }); // 空の件名は反映しない
});
customerInput.addEventListener('input', () => {
  const customer = customerInput.value.trim();
  if (customer !== '') updateEditing({ customer }); // 必須項目なので空は反映しない
});
contactInput.addEventListener('input', () => updateEditing({ contact: contactInput.value.trim() }));
categorySelect.addEventListener('change', () => updateEditing({ category: categorySelect.value }));
dueInput.addEventListener('change', () => updateEditing({ due: dueInput.value }));
assigneeInput.addEventListener('input', () => updateEditing({ assignee: assigneeInput.value.trim() }));
descInput.addEventListener('input', () => {
  if (descInput.value.trim() !== '') updateEditing({ description: descInput.value }); // 必須項目なので空は反映しない
});
memoInput.addEventListener('input', () => updateEditing({ memo: memoInput.value }));

// 詳細画面からのステータス変更：移動先ステータスの末尾に入る（ドラッグ&ドロップと同じ扱い）
statusSelect.addEventListener('change', () => {
  const inquiry = findEditing();
  if (!inquiry) return;
  moveInquiry(inquiry.id, statusSelect.value);
  renderBoard();
});

priorityRadios.forEach((r) => {
  r.addEventListener('change', () => {
    if (!r.checked) return;
    const inquiry = findEditing();
    if (!inquiry) return;
    // 優先度を変えた問い合わせは、同じリストの末尾に移してから優先度順に並べ直す
    // → 変更後の優先度の中で対応期限に応じた位置（期限も同じものがあればその末尾）に入る
    inquiry.priority = r.value;
    inquiries = [...inquiries.filter((q) => q.id !== inquiry.id), inquiry];
    sortListByPriority(inquiry.listId);
    renderBoard();
  });
});

document.getElementById('btn-close').addEventListener('click', closeDetail);
overlayEl.addEventListener('click', (e) => {
  if (e.target === overlayEl) closeDetail(); // 背景クリックでも閉じる
});
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && !overlayEl.hidden) closeDetail();
});

// 削除（確認ダイアログで OK のときだけ削除する）
document.getElementById('btn-delete').addEventListener('click', () => {
  const inquiry = findEditing();
  if (!inquiry) return;
  if (!window.confirm(`問い合わせ「${inquiry.title}」を削除しますか？\nこの操作は取り消せません。`)) return;
  inquiries = inquiries.filter((q) => q.id !== editingId);
  closeDetail();
  renderBoard();
});

// ---------- ツールバー：全リストの優先度順並べ替え ----------
document.getElementById('btn-sort').addEventListener('click', () => {
  sortAllByPriority();
  renderBoard();
});

// ---------- 初期表示 ----------
renderBoard();
