# 問い合わせ管理アプリ フロントエンド設計書

## 1. 文書情報

| 項目 | 内容 |
| --- | --- |
| 文書名 | 問い合わせ管理アプリ フロントエンド設計書 |
| 版数 | 1.0 |
| 作成日 | 2026-10-31 |
| 最終更新日 | 2026-10-31 |
| 作成者 | KeiT0773 |
| ステータス | 作成中（レビュー待ち） |
| 上位文書 | [API 設計書](api-design.md)、[画面要件書](screen-requirements.md) |
| 関連文書 | [要件定義書](requirements.md)、[機能要件書](functional-requirements.md)、[データ設計書](data-design.md)、[技術スタック](tech-stack.md)、画面モック（[mock/](../mock/)） |

本書は、フロントエンド（Next.js）の **ディレクトリ構成、コンポーネント構成、状態とデータの流れ、API 呼び出しの方針、型定義、表示ルール** を定義する。画面に何を置くかは[画面要件書](screen-requirements.md)、サーバーとの取り決めは[API 設計書](api-design.md)を正とし、本書はそれらをどう実装するかを定める。

本書は、タスク管理アプリのフロントエンド設計書の構成と方針を踏襲する。変えた点は「10. 設計上の決定事項」の「タスク管理アプリとの違い」欄に示す。

### 1.1 変更履歴

| 版数 | 日付 | 変更内容 | 変更者 |
| --- | --- | --- | --- |
| 1.0 | 2026-10-31 | 初版作成。FR-01〜FR-10 と SC-01・SC-02 のすべてを対象に定義 | KeiT0773 |

---

## 2. 設計方針

| No | 事項 | 決定 | 理由 |
| --- | --- | --- | --- |
| 1 | Next.js の使い方 | App Router で 1 ページ（`/`）だけを作り、`next.config.ts` に `output: 'export'` を指定して静的ファイルに書き出す。ボードはクライアントコンポーネント（`'use client'`）として作り、データはブラウザから API を呼んで取得する。サーバーでだけ動く機能（サーバーでのデータ取得、Route Handlers、`rewrites`、画像の最適化など）は使わない | [技術スタック](tech-stack.md) 4.・8. No.1。本番は EC2 上の nginx が書き出したファイルを返すだけで、Next.js のサーバーは動かない |
| 2 | バックエンドとの接続 | API の URL の先頭を環境変数 `NEXT_PUBLIC_API_BASE_URL` で切り替える。開発時は `http://localhost:3001`（Rails を直接呼ぶ。Rails 側で CORS を許可）、本番は空文字（画面と同じドメインの `/api` を呼ぶ） | [技術スタック](tech-stack.md) 8. No.2、[API 設計書](api-design.md) 2. 方針 10。9. を参照 |
| 3 | 状態管理 | 状態管理ライブラリは導入しない。取得したリストと問い合わせは、カスタムフック `useBoard` が React 標準の `useState` / `useEffect` で保持する | 画面は 1 つ、データは最大 300 件程度（[要件定義書](requirements.md) 5.1）。[技術スタック](tech-stack.md) 2.「必要になるまでライブラリを追加しない」 |
| 4 | スタイル | CSS Modules を使い、画面モック `mock/style.css` をコンポーネントごとの `*.module.css` に分割して移植する。全体に効かせる指定（`*` と `body`）だけをグローバルの `globals.css` に置く | モックで確認済みの見た目をそのまま再現できる。Next.js が CSS Modules を標準で扱う |
| 5 | 区分値の表示名 | 種別・優先度の表示名（質問 / 不具合 / 要望 / その他、高 / 中 / 低）への変換はフロントエンドの責務とする。リストの表示名は API の `name` をそのまま使う | [API 設計書](api-design.md) 2. 方針 7 |
| 6 | 期限超過・未割当の判定 | フロントエンドが表示のたびに判定する | [データ設計書](data-design.md) 5.4。API は判定結果を返さない |
| 7 | 通信エラーの通知 | **取得** の失敗はボードの代わりに文言を表示する。**登録** の失敗は登録フォームの中、**編集** の失敗はその項目の下、**削除** の失敗は問い合わせ詳細のフッターに表示し、入力した内容は消さない。**移動・全リストの並べ替え・問い合わせ詳細を開く** 操作の失敗は、ボードの上部に表示する | FR-09「保存されていないことを利用者に分かるように通知する」。タスク管理アプリと同じ考え方で、操作した場所で伝える |
| 8 | 書き込み後の画面反映 | 書き込みに成功したら、応答の 1 件を手元の一覧に差し込むのではなく、影響を受けたリストを `GET /api/inquiries?listId=` で取り直して置き換える（全リストの並べ替えは全件） | サーバーがリスト内を並べ直すため、他の問い合わせの `displayOrder` も変わりうる（[API 設計書](api-design.md) 8.〜12.「画面へ反映する方法」）。並べ替えの規則をフロントエンドに持たずに済む。取り直しのたびに、ほかのメンバーの変更も反映される |
| 9 | ドラッグ&ドロップだけは楽観更新する | ドロップした瞬間に、API の応答を待たずに手元の並びを変える。失敗したら取り直して元に戻す | ドロップ直後に元の位置へ戻ると操作が失敗したように見える。ここで行うのは「ドロップした位置に置く」だけで、並べ替えの規則は持たない |
| 10 | ほかのメンバーとの同時利用 | 編集は **変えた項目だけ** を送る（`PATCH`）。問い合わせ詳細を開くときは、その 1 件を `GET /api/inquiries/{id}` で取り直してから開く。操作した問い合わせが 404（ほかのメンバーが削除した）なら、その旨を通知して一覧を取り直す | [要件定義書](requirements.md) 決定事項 No.17、[API 設計書](api-design.md) 2.3。開いた時点の最新の値を下書きにすることで、古い値を見ながら編集することを減らす |

---

## 3. ディレクトリ構成

`frontend/` の中の構成を次のとおり定める。役割ごとにディレクトリを分け、コンポーネントは 1 つにつき 1 ディレクトリ（`.tsx` と `.module.css` を同じ場所に置く）とする。

```
frontend/
├── next.config.ts              output: 'export' の指定
├── .env.development            NEXT_PUBLIC_API_BASE_URL=http://localhost:3001（コミットする。秘密の値ではない）
├── .env.production             NEXT_PUBLIC_API_BASE_URL=（空。同じドメインの /api を呼ぶ）
├── vitest.config.ts            テストの設定
├── package.json
└── src/
    ├── app/
    │   ├── layout.tsx          HTML の骨組み（<html lang="ja">、タイトル）。サーバーコンポーネント（書き出し時に HTML になる）
    │   ├── page.tsx            画面全体（AppHeader + Board）
    │   └── globals.css         グローバルスタイル（* と body のみ）
    ├── types/
    │   └── inquiry.ts          API の要求・応答に対応する型（7.）
    ├── api/
    │   ├── client.ts           fetch の共通処理（apiGet, apiPost, apiPatch, apiPut, apiDelete, ApiError）
    │   ├── lists.ts            GET /api/lists
    │   └── inquiries.ts        GET / POST / PATCH / PUT position / POST sort / DELETE（6.1）
    ├── hooks/
    │   └── useBoard.ts         リストと問い合わせの取得・保持と、登録・編集・移動・並べ替え・削除
    ├── utils/
    │   ├── date.ts             日付の書式変換と期限超過の判定
    │   ├── errorMessage.ts     ApiError から表示文言への変換（6.3）
    │   └── board.ts            ドロップ結果を一覧に反映する純粋関数（applyMove, dragEndToMove）
    ├── constants/
    │   └── labels.ts           種別・優先度の表示名と並び順
    ├── components/
    │   ├── AppHeader/          ヘッダー
    │   ├── Board/              ボード（3 列の親。'use client'。読み込み中・エラーの表示もここ）
    │   ├── BoardToolbar/       ヘッダーとボードの間のツールバー（「優先度順に並べ替え」）
    │   ├── BoardList/          1 つのリスト（列）
    │   ├── InquiryCard/        1 件の問い合わせのカード
    │   ├── AddInquiryForm/     「＋ 問い合わせを登録」ボタンと入力フォーム（「未対応」列だけ）
    │   ├── InquiryDetail/      問い合わせ詳細（SC-02）のモーダル
    │   ├── PriorityBadge/      優先度の色付きバッジ
    │   └── CategoryTag/        種別の色付きラベル
    └── test/
        └── setup.ts            テストの共通設定
```

`components/` 以下の各ディレクトリには `<名前>.tsx`、`<名前>.module.css`、必要に応じて `<名前>.test.tsx` を置く。`'use client'` は `Board` の先頭にだけ書く（`Board` から読み込まれる部品は自動的にクライアントで動く）。

---

## 4. コンポーネント構成

### 4.1 ツリー

```
page.tsx
├── AppHeader
└── Board                         ← 'use client'。useBoard() でデータを取得・操作。DragDropContext を張る
    ├── BoardToolbar              ← ヘッダーの直下・リストの外。「優先度順に並べ替え」
    ├── （移動・並べ替え・詳細を開く操作に失敗したときの文言）
    ├── BoardList（未対応）        ← Droppable。見出しに件数
    │   ├── InquiryCard           ← Draggable。クリックで InquiryDetail を開く
    │   │   ├── PriorityBadge
    │   │   └── CategoryTag
    │   ├── InquiryCard ...
    │   └── AddInquiryForm        ← 「未対応」列の最下部にだけ置く
    ├── BoardList（対応中）        ← AddInquiryForm は無い
    ├── BoardList（完了）          ← AddInquiryForm は無い
    └── InquiryDetail             ← 選択中の問い合わせがあるときだけ描画。ボードの手前に重ねる
```

### 4.2 各コンポーネントの責務と props

| コンポーネント | 責務 | props | 対応する要件 |
| --- | --- | --- | --- |
| `page.tsx` | `AppHeader` と `Board` を縦に並べる。それ以外の処理は持たない | なし | — |
| `AppHeader` | 画面上部の青い帯にアプリ名「問い合わせ管理ボード」を表示する | なし | SC-01 |
| `Board` | `useBoard` を呼び、状態に応じて「読み込み中」「エラー文言」「3 つの `BoardList`」のいずれかを描画する。**選択中の問い合わせの `id`**（`selectedId`）を持ち、該当があれば `InquiryDetail` を描画する。`DragDropContext` を張り、ドロップ時に `moveInquiry` を呼ぶ。`BoardToolbar` から `sortByPriority` を呼ぶ。移動・並べ替え・詳細を開く操作の失敗の文言（`actionError`）を上部に表示する | なし | SC-01、SC-02 |
| `BoardToolbar` | 「優先度順に並べ替え」ボタンを持つ。押すと `onSort` を呼び、終わるまでボタンを無効にして「並べ替え中…」を表示する | `onSort: () => Promise<void>` | FR-10、画面要件書 3. |
| `BoardList` | リストの見出し（`name`）と件数（`n件`）、問い合わせの一覧を縦に描画する。`list.id === 'open'` のときだけ最下部に `AddInquiryForm` を置く。一覧の領域を `Droppable`（`droppableId = list.id`）にし、問い合わせが多いときは列の中だけをスクロールさせる | `list: BoardList`、`inquiries: Inquiry[]`、`onAdd?: (input: InquiryCreateInput) => Promise<void>`（「未対応」だけに渡す）、`onCardClick: (id: number) => void` | 画面要件書 3.・5.1、FR-01、FR-04 |
| `InquiryCard` | 問い合わせ 1 件のカード。1 行目に優先度バッジと件名、2 行目に問い合わせ者（「様」付き）と対応者（未割当は赤字）、3 行目に種別ラベルと対応期限（期限超過は強調）を表示する。`Draggable` でつかんで動かせ、クリックまたは Enter で `onClick` を呼ぶ | `inquiry: Inquiry`、`index: number`、`onClick: () => void` | 画面要件書 3.、FR-06、FR-07、FR-08 |
| `AddInquiryForm` | 閉じているときは「＋ 問い合わせを登録」ボタンを表示する。押すと件名・問い合わせ者・問い合わせ内容の入力欄、種別の選択、優先度の選択、「登録」「キャンセル」を表示する。入力内容・開閉・送信中・失敗の状態を自分で持ち、送信は `onSubmit` に委ねる（8.5） | `onSubmit: (input: InquiryCreateInput) => Promise<void>` | FR-01、画面要件書 5.1 |
| `InquiryDetail` | 問い合わせ詳細（SC-02）のモーダル。全項目の入力欄と受付日の表示、「閉じる」、フッターに「問い合わせを削除」を持つ。項目ごとの下書き・保存中・失敗の状態を自分で持ち、項目が確定したときに **その項目だけ** を `onSave` に渡す。ステータスを選び直したら `onMove` を呼ぶ。削除は確認ダイアログを経て `onDelete` を呼ぶ（8.6） | `inquiry: Inquiry`、`lists: BoardList[]`、`onSave: (input: InquiryUpdateInput) => Promise<void>`、`onMove: (listId: ListId) => Promise<void>`、`onDelete: () => Promise<void>`、`onClose: () => void` | SC-02、FR-02〜FR-04、FR-06〜FR-08 |
| `PriorityBadge` | 優先度を表示名（高 / 中 / 低）と色で表示する | `priority: Priority` | FR-08 |
| `CategoryTag` | 種別を表示名と色で表示する | `category: Category` | 画面要件書 3. |

`AddInquiryForm` と `InquiryDetail` が API を直接呼ばず関数を受け取るのは、**問い合わせの一覧を持っているのが `useBoard` だけ** だからである。一覧の更新は `useBoard` が行い、これらの部品は「送信して、成功か失敗かを知る」ことだけに責任を持つ。テストでは渡した関数の呼ばれ方を見るだけで済む。タスク管理アプリと同じ分け方である。

---

## 5. 状態とデータの流れ

### 5.1 取得の流れ

アプリを開いたとき（再読み込みを含む）に、リストと問い合わせを取得する（FR-09）。

```
Board が描画される
  → useBoard の useEffect が起動
  → GET /api/lists と GET /api/inquiries を同時に要求（Promise.all）
  → 両方が返ったら state に保存し、Board が再描画される
  → Board は lists を順に BoardList にし、inquiries を listId で振り分けて渡す
```

API は `listId`・`displayOrder` の順に返す（[API 設計書](api-design.md) 6.）ため、フロントエンドでは並べ替えを行わず、**`listId` による振り分けだけ** を行う。

ほかのメンバーの変更は、自動では画面に反映しない（[要件定義書](requirements.md) 決定事項 No.17）。利用者がブラウザで再読み込みしたとき、または自分の書き込みのあとに取り直したときに反映される。

### 5.2 `useBoard` が持つ状態と返すもの

| 状態 | 型 | 初期値 | 意味 |
| --- | --- | --- | --- |
| `lists` | `BoardList[]` | `[]` | 取得したリスト |
| `inquiries` | `Inquiry[]` | `[]` | 取得した問い合わせ |
| `loading` | `boolean` | `true` | 取得中かどうか |
| `error` | `ApiError \| null` | `null` | 取得に失敗した場合のエラー（ボードを表示できない状態） |

| 関数 | 呼ぶ API | 取り直す範囲 |
| --- | --- | --- |
| `addInquiry(input)` | `POST /api/inquiries` | 「未対応」 |
| `refreshInquiry(id)` | `GET /api/inquiries/{id}` | その 1 件を手元の一覧で置き換える（詳細を開くとき。5.4） |
| `updateInquiry(id, input)` | `PATCH /api/inquiries/{id}` | その問い合わせのリスト |
| `moveInquiry(id, to)` | `PUT /api/inquiries/{id}/position` | 移動元と移動先（同じなら 1 つ） |
| `sortByPriority()` | `POST /api/inquiries/sort` | 全件 |
| `deleteInquiry(id)` | `DELETE /api/inquiries/{id}` | 削除した問い合わせのリスト |

一覧の置き換えは、`setInquiries(prev => [...prev.filter(q => q.listId !== listId), ...fetched])` のように **直前の状態を引数に取る形** で行う。関数を作った時点の一覧を参照すると、その後の別の操作の結果を上書きしてしまうため。`useEffect` のクリーンアップで「取り消し済み」フラグを立て、部品が消えた後に応答が返っても状態を更新しないようにする。

**404 の扱い**：書き込み・取得で 404 が返ったとき（ほかのメンバーが削除した。[API 設計書](api-design.md) 2.3）は、`GET /api/inquiries` で全件を取り直してから、`ApiError` を投げる。呼び出し側はいつもどおり文言を表示し、取り直しによって画面からその問い合わせが消える。

### 5.3 登録の流れ

```
AddInquiryForm で「登録」を押す
  → 入力チェック（8.5）。必須の 3 項目に空があれば送らない
  → onSubmit（= useBoard の addInquiry）を呼ぶ
  → POST /api/inquiries に { title, customerName, content, category, priority } を送る
  → 成功（201）したら GET /api/inquiries?listId=open で「未対応」を取り直して置き換える
  → 新しい問い合わせが優先度順の位置に表示される
  → AddInquiryForm は入力欄を空にして開いたままにする（続けて登録できる）
```

失敗したとき（422・500・接続不可）は `ApiError` を投げ、一覧は変えない。`AddInquiryForm` がフォームの中に文言を出し、入力内容は残す。登録の失敗は `useBoard` の `error` には入れない（ボードは表示し続けるため）。

### 5.4 問い合わせ詳細を開く流れ

```
ボード上のカードをクリック（または Enter）
  → Board が useBoard の refreshInquiry(id) を呼ぶ
  → GET /api/inquiries/{id} で最新の 1 件を取得し、手元の一覧のその 1 件を置き換える
  → 成功したら Board が selectedId に id を入れ、InquiryDetail が最新の値で描画される
  → 404 なら（ほかのメンバーが削除した）全件を取り直し、ボード上部に文言を出す。詳細は開かない
  → 接続できないなどの失敗も、ボード上部に文言を出し、詳細は開かない
```

開く前に 1 件を取り直すのは、ほかのメンバーが変更したあとの値を下書きにするためである（2. 方針 10）。タスク管理アプリは利用者が 1 名で手元の一覧が常に最新だったため、取り直さなかった。取り直しは 1 件だけで速いため、開くまでの待ちはほとんど気にならない。

### 5.5 編集の流れ

```
InquiryDetail で項目が確定する（8.6）
  → onSave（= useBoard の updateInquiry）に、確定した 1 項目だけを渡す（例：{ assignee: '小林' }）
  → PATCH /api/inquiries/{id} に送る
  → 成功（200）したら、その問い合わせのリストを GET /api/inquiries?listId= で取り直して置き換える
  → InquiryDetail に渡る inquiry も新しい値になる。優先度を変えたときは位置が変わる
```

失敗したときは `ApiError` を投げ、一覧は変えない。`InquiryDetail` がその項目の下に文言を出し、入力は残す。

### 5.6 移動の流れ

ドラッグ&ドロップと、問い合わせ詳細でのステータスの選択の 2 通りがある（FR-04）。

```
【ドラッグ&ドロップ】
問い合わせをドロップする
  → Board の onDragEnd が結果を dragEndToMove（utils/board.ts）で { id, listId, displayOrder } に変換する
    （ドロップ先が無い、または元と同じ位置なら null を返し、何もしない）
  → useBoard の moveInquiry を呼ぶ
  → まず setInquiries(prev => applyMove(prev, id, listId, displayOrder)) で手元の並びを変える（楽観更新。方針 9）
  → PUT /api/inquiries/{id}/position に { listId, displayOrder } を送る
  → 成功したら、移動元と移動先のリストを取り直して置き換える
  → 失敗したら全件を取り直して元に戻し、ApiError を投げる → Board が上部に文言を出す

【問い合わせ詳細でのステータスの選択】
InquiryDetail でステータスを選び直す
  → onMove（= useBoard の moveInquiry）に { listId } だけを渡す（displayOrder は送らない → 移動先の末尾）
  → PUT /api/inquiries/{id}/position に送る（楽観更新はしない）
  → 成功したら、移動元と移動先のリストを取り直す。詳細は開いたまま（ステータスの表示が新しい値になる）
  → 失敗したら InquiryDetail がステータスの欄の下に文言を出し、選択を元の値に戻す
```

`applyMove(inquiries, id, toListId, toIndex)` は、一覧からその問い合わせを取り除き、`listId` を書き換えて、移動先のリストの `toIndex` 番目に差し込んだ新しい配列を返す純粋関数である。並びの計算だけを単体テストで確かめられるように切り出す。

### 5.7 全リストの優先度順並べ替えの流れ

```
BoardToolbar の「優先度順に並べ替え」を押す
  → onSort（= useBoard の sortByPriority）を呼ぶ
  → POST /api/inquiries/sort を送る（body なし）
  → 成功（204）したら GET /api/inquiries で全件を取り直し、一覧を丸ごと置き換える
```

失敗したときは `ApiError` を投げ、一覧は変えない。`Board` が上部に文言を出す。楽観更新はしない（並べ替えの規則をフロントエンドに持たないため）。

### 5.8 削除の流れ

```
InquiryDetail の「問い合わせを削除」を押す
  → window.confirm で確認ダイアログを出す（8.6）。キャンセルなら何もしない
  → OK なら onDelete（= useBoard の deleteInquiry）を呼ぶ
  → まず一覧からその問い合わせの listId を引いておく（応答に本文が無いため）
  → DELETE /api/inquiries/{id} を送る
  → 成功（204）したら、そのリストを取り直して置き換える
  → 一覧からその問い合わせが消えるので、Board は selectedId を null に戻し、詳細を閉じる
```

失敗したときは `ApiError` を投げ、一覧は変えない。`InquiryDetail` はフッターに文言を出し、開いたままにする。404（ほかのメンバーが先に削除していた）のときは、5.2 のとおり全件を取り直すため、その問い合わせは画面から消え、詳細も閉じる。

---

## 6. API 呼び出しの方針

### 6.1 共通処理

`src/api/client.ts` に共通処理を置く。個々の API（`lists.ts`、`inquiries.ts`）はこれを呼ぶだけの薄い関数とし、パスと要求・戻り値の型だけを持つ。

```ts
const BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? '';

export async function apiGet<T>(path: string): Promise<T>;
export async function apiPost<TBody, T>(path: string, body?: TBody): Promise<T>;
export async function apiPatch<TBody, T>(path: string, body: TBody): Promise<T>;
export async function apiPut<TBody, T>(path: string, body: TBody): Promise<T>;
export async function apiDelete<T>(path: string): Promise<T>;
```

- 実際の URL は `BASE_URL + path`（例：開発時は `http://localhost:3001/api/inquiries`、本番は `/api/inquiries`）。
- `NEXT_PUBLIC_` で始まる環境変数は、ビルド時に値がコードへ埋め込まれる。本番用のビルド（`npm run build`）では `.env.production` の空文字が入る。
- body を持つ関数は `Content-Type: application/json` を付け、`JSON.stringify` して送る。`apiPost` は body が `undefined` のときは何も付けない（`POST /api/inquiries/sort` のため）。

| 状況 | 動作 |
| --- | --- |
| `fetch` 自体が失敗した（サーバー停止、ネットワーク未接続、CORS の拒否など） | `ApiError(null, 'サーバーに接続できません')` を投げる |
| 応答が `2xx` 以外 | 本文を Problem Details（[API 設計書](api-design.md) 2.1）として読み、`ApiError(status, detail)` を投げる。本文が読めなければ `title` または HTTP ステータスの文言を使う。422 は `detail` に項目ごとのメッセージが連結されているので、`errors` は読まない |
| 応答が `204 No Content` | 本文を読まず、`undefined` を返す |
| 応答がそれ以外の `2xx` | 本文の JSON を `T` として返す |

`inquiries.ts` の関数は次の 7 つになる。

```ts
export function getInquiries(listId?: ListId): Promise<Inquiry[]>;                    // GET /api/inquiries[?listId=]
export function getInquiry(id: number): Promise<Inquiry>;                             // GET /api/inquiries/{id}
export function createInquiry(input: InquiryCreateInput): Promise<Inquiry>;           // POST /api/inquiries
export function updateInquiry(id: number, input: InquiryUpdateInput): Promise<Inquiry>; // PATCH /api/inquiries/{id}
export function moveInquiry(id: number, input: InquiryMoveInput): Promise<Inquiry>;   // PUT /api/inquiries/{id}/position
export function sortInquiries(): Promise<void>;                                       // POST /api/inquiries/sort
export function deleteInquiry(id: number): Promise<void>;                             // DELETE /api/inquiries/{id}
```

### 6.2 `ApiError`

```ts
export class ApiError extends Error {
  constructor(readonly status: number | null, message: string);
}
```

`status` が `null` のときは「サーバーに到達できなかった」、数値のときは「サーバーがその HTTP ステータスで応答した」ことを表す。呼び出し側はこの 1 種類だけを扱えばよい。

### 6.3 エラー時の表示文言

| `status` | 表示する文言 |
| --- | --- |
| `null` | サーバーに接続できません。バックエンドが起動しているか確認してください。 |
| `404` | この問い合わせは、ほかのメンバーによって削除されています。 |
| `500` | サーバーでエラーが発生しました。 |
| その他 | `ApiError.message`（API が返した `detail`）をそのまま表示する。422 なら「件名を入力してください」のような日本語になる |

この変換は `src/utils/errorMessage.ts` の `errorMessage(error: ApiError): string` に置き、すべての失敗の表示から使う。同じ種類のエラーは画面のどこで起きても同じ文言にするため。

---

## 7. 型定義

`src/types/inquiry.ts` に、[API 設計書](api-design.md) 4. のリソース形式と 1 対 1 で対応する型を定義する。項目名・型・NULL 可否を API 設計書から変えてはならない。

| 型 | 定義 | 対応 |
| --- | --- | --- |
| `Category` | `'question' \| 'bug' \| 'request' \| 'other'` | API 設計書 2. 方針 7 |
| `Priority` | `'high' \| 'medium' \| 'low'` | 同上 |
| `ListId` | `'open' \| 'working' \| 'closed'` | 同上 |
| `BoardList` | `{ id: ListId; name: string; displayOrder: number }` | API 設計書 4.1 |
| `Inquiry` | `{ id: number; title: string; customerName: string; contact: string \| null; category: Category; content: string; memo: string \| null; assignee: string \| null; receivedOn: string; dueOn: string \| null; priority: Priority; listId: ListId; displayOrder: number; createdAt: string; updatedAt: string }` | API 設計書 4.2 |
| `InquiryCreateInput` | `{ title: string; customerName: string; content: string; category: Category; priority: Priority }` | API 設計書 8. の要求 body |
| `InquiryUpdateInput` | `Partial<{ title: string; customerName: string; contact: string \| null; category: Category; content: string; memo: string \| null; assignee: string \| null; dueOn: string \| null; priority: Priority }>` | API 設計書 9. の要求 body（変える項目だけ） |
| `InquiryMoveInput` | `{ listId: ListId; displayOrder?: number }` | API 設計書 10. の要求 body |

- 日付（`receivedOn`・`dueOn`）は `YYYY-MM-DD` の文字列、日時は ISO 8601（UTC）の文字列のまま保持し、`Date` 型には変換しない。
- `InquiryUpdateInput` は「送る項目だけを持つ」形にする。任意項目（`contact`・`memo`・`assignee`・`dueOn`）を空にしたときは `''` ではなく `null` を入れて送る。
- `InquiryCreateInput` の `category`・`priority` は API では省略可だが、フロントエンドでは常に送る（フォームで選んだ値をそのまま送る方が、既定値という暗黙の規則に頼らずに済む）。

---

## 8. 表示ルール

### 8.1 優先度・種別

| `priority` | 表示名 | 色 |
| --- | --- | --- |
| `high` | 高 | `#de350b`（赤） |
| `medium` | 中 | `#ff991f`（橙） |
| `low` | 低 | `#36b37e`（緑） |

| `category` | 表示名 | 文字色 / 背景色 |
| --- | --- | --- |
| `question` | 質問 | `#0747a6` / `#deebff` |
| `bug` | 不具合 | `#bf2600` / `#ffebe6` |
| `request` | 要望 | `#403294` / `#eae6ff` |
| `other` | その他 | `#42526e` / `#dfe1e6` |

表示名と選択肢の並び順は `src/constants/labels.ts` に定数として持つ。色は各部品の `.module.css` に持つ。値は画面モック `mock/style.css` と同じ。

### 8.2 カード表面の表示

| 項目 | 表示 |
| --- | --- |
| 問い合わせ者 | `<名前> 様`（例：`山田 太郎 様`） |
| 対応者 | 設定済みなら `対応者 <名前>`。`null` なら `対応者 未割当` を赤字（`#de350b`）・太字 |
| 対応期限 | `null` なら空欄（行の高さは確保する）。期限超過でなければ `期限 MM/DD`。期限超過なら `期限 MM/DD（期限切れ）` を赤字・太字 |

### 8.3 期限超過の判定

[データ設計書](data-design.md) 5.4 の基準「日本時間の今日の日付が `due_on` より後、かつ完了以外」を、次のとおり実装する。

- 「今日」は端末のローカル日付とする。[要件定義書](requirements.md) 5.1 の想定端末は日本国内にあるため、日本時間と一致する。
- 比較は `YYYY-MM-DD` の文字列どうしで行う（この形式は文字列の大小と日付の前後が一致する）。

```
isOverdue(inquiry) = inquiry.dueOn !== null
                  && inquiry.dueOn < today()
                  && inquiry.listId !== 'closed'
```

`today()` は描画のたびに求める。静的書き出しのため、ビルドした日の日付を HTML に埋め込まないよう、判定はクライアントでだけ行う（`Board` 以下はすべてクライアントコンポーネント）。

### 8.4 問い合わせ詳細の日付

受付日は `受付日 YYYY/MM/DD` の形で表示する（画面モックと同じ）。対応期限は `<input type="date">` に `YYYY-MM-DD` のまま渡す。

### 8.5 問い合わせ登録フォームの挙動

[画面要件書](screen-requirements.md) 5.1「問い合わせ登録の入力欄」と画面モック `mock/script.js` の `renderAddForm` に合わせる。

#### `AddInquiryForm` が持つ状態

| 状態 | 型 | 初期値 | 意味 |
| --- | --- | --- | --- |
| `open` | `boolean` | `false` | 入力欄を開いているか |
| `title`・`customerName`・`content` | `string` | `''` | 入力中の値 |
| `category` | `Category` | `'question'` | 選択中の種別 |
| `priority` | `Priority` | `'medium'` | 選択中の優先度 |
| `missing` | `('title' \| 'customerName' \| 'content')[]` | `[]` | 直前の「登録」で空だった必須項目。赤枠と文言に使う |
| `submitting` | `boolean` | `false` | 送信中。`true` の間は「登録」「キャンセル」を押せなくする |
| `error` | `ApiError \| null` | `null` | 直前の送信で失敗したエラー |

#### 操作と動作

| 操作 | 動作 |
| --- | --- |
| 「＋ 問い合わせを登録」を押す | `open = true` にし、件名の入力欄にフォーカスを当てる |
| 入力する | `maxLength`（件名 100、問い合わせ者 50、問い合わせ内容 2000）で上限を超えて入力できないようにする（[データ要件書](data-requirements.md) 2.1）。入力し直した欄は `missing` から外し、赤枠を消す |
| 「登録」を押す（件名・問い合わせ者の欄で Enter も同じ） | 3 項目の前後の空白（全角の空白を含む）を除く。空の項目があれば **送らず**、`missing` に入れて赤枠を付け、「件名・問い合わせ者を入力してください」のように空の項目名を「・」でつないだ文言を `role="alert"` で表示し、最初の空の欄にフォーカスを移す（FR-01、画面要件書 5.1）。空が無ければ `submitting = true` にして `onSubmit` を呼ぶ |
| 送信に成功 | 入力値・`missing`・`error` を初期値に戻し、入力欄は **開いたまま** 件名にフォーカスを戻す（続けて登録できる） |
| 送信に失敗 | `error` に入れ、フォームの中に `errorMessage(error)`（6.3）を `role="alert"` で表示する。入力内容は消さない |
| 「キャンセル」を押す、またはフォームの中で Escape | `open = false` にし、すべての状態を初期値に戻す |

問い合わせ内容（`<textarea>`）の中の Enter は改行とし、送信しない。

#### 配置

「未対応」の `BoardList` の中で、一覧（スクロールする領域）の **外側の最下部** に置く。問い合わせが多くて列がスクロールしても「＋ 問い合わせを登録」が常に見えるようにするため。

### 8.6 問い合わせ詳細（SC-02）の挙動

[画面要件書](screen-requirements.md) 5.2 と画面モックの詳細モーダルに合わせる。モックは入力のたびに即時反映していたのに対し、実装では **項目ごとに確定したときにサーバーへ保存する**。「保存」ボタンは置かない。

#### `InquiryDetail` が持つ状態

| 状態 | 意味 |
| --- | --- |
| 項目ごとの下書き（`title`・`customerName`・`contact`・`category`・`content`・`memo`・`assignee`・`dueOn`・`priority`・`listId`） | `inquiry` から初期化する。`null` の項目は入力欄に合わせて `''` にする |
| `saving` | 保存中かどうか。見出しの横に「保存中…」を出す。入力欄は無効にしない。連続して確定した保存は順番に送る（直列化） |
| `deleting` | 削除中かどうか。「問い合わせを削除」ボタンを無効にし、文言を「削除中…」にする |
| `error` | 直前の保存・移動・削除で失敗したエラーと、文言を出す場所（項目名、`'listId'`、または `'delete'`） |

`Board` は `InquiryDetail` を `key={inquiry.id}` で描画し、別の問い合わせを開いたときは作り直す（下書きが混ざらない）。ラベルと入力欄は `<label htmlFor>` と `id` で結ぶ。

#### 保存の契機と動作

| 項目 | 入力欄 | 保存の契機 | 送る値 |
| --- | --- | --- | --- |
| 件名 | `<input type="text" maxLength={100}>` | blur、または Enter | `{ title }` |
| 問い合わせ者 | `<input type="text" maxLength={50}>` | blur、または Enter | `{ customerName }` |
| 連絡先 | `<input type="text" maxLength={100}>` | blur、または Enter | `{ contact }`（空なら `null`） |
| 種別 | `<select>` | change | `{ category }` |
| ステータス | `<select>`（選択肢は `lists` から作る） | change | `onMove(listId)`（5.6。保存ではなく移動） |
| 対応期限 | `<input type="date">` | change。空にすると解除 | `{ dueOn }`（空なら `null`） |
| 問い合わせ内容 | `<textarea maxLength={2000}>` | blur。Enter は改行 | `{ content }` |
| 対応メモ | `<textarea maxLength={2000}>` | blur。Enter は改行 | `{ memo }`（空なら `null`） |
| 対応者 | `<input type="text" maxLength={50}>` | blur、または Enter | `{ assignee }`（空なら `null`） |
| 優先度 | ラジオボタン 3 つ（ラベルは `PriorityBadge`） | change | `{ priority }` |

保存の手順はどの項目でも同じで、次のとおり。

1. 前後の空白（全角の空白を含む）を除く。**必須項目（件名・問い合わせ者・問い合わせ内容）が空なら保存せず、下書きを `inquiry` の値に戻す**（FR-02「空にはできない」。文言は出さない）。
2. **現在の `inquiry` と同じ値なら送らない**（フォーカスが外れただけで何も変えていないときに通信しない）。
3. `saving = true` にして、その項目だけを `onSave` に渡す。
4. 成功したら、その項目のエラーを消し、下書きを送った値にそろえる（他の項目の下書きは触らない）。
5. 失敗したら、その項目の下に `errorMessage(error)` を `role="alert"` で表示する。下書きは消さない（打ち直さずに再送できる）。
6. `saving = false` に戻す。

#### フッターの「問い合わせを削除」

| 項目 | 内容 |
| --- | --- |
| 位置 | モーダルの最下部、区切り線を引いたフッターの右寄せ。ボード上のカード表面には置かない（画面要件書 3.） |
| 見た目 | 白背景・赤枠（`#de350b`）・赤文字。hover で赤背景・白文字（画面モックと同じ） |
| 押したとき | `window.confirm` で「問い合わせ「<件名>」を削除しますか？」と「この操作は取り消せません。」を表示する（FR-03、画面要件書 5.2）。OK なら `deleting = true` にして `onDelete()` を呼ぶ。キャンセルなら何もしない |
| 成功 | `Board` が詳細を閉じる（5.8） |
| 失敗 | フッターのボタンの横に「削除できませんでした。＋ 6.3 の文言」を `role="alert"` で表示する。モーダルは開いたまま |

確認ダイアログはブラウザ標準の `window.confirm` を使う（[画面要件書](screen-requirements.md) 5.2「ブラウザ標準のものでよい」）。テストでは `vi.spyOn(window, 'confirm')` で OK・キャンセルを差し替える。

#### 開閉

| 操作 | 動作 |
| --- | --- |
| ボード上のカードをクリック（または Enter） | 5.4 のとおり最新の 1 件を取得してから開き、件名の入力欄にフォーカスを当てる |
| 「閉じる」ボタン、背景のクリック、Escape | `onClose` を呼び、`Board` が `selectedId` を `null` にする。保存中でも閉じてよい（保存はそのまま続く） |
| 削除に成功 | `Board` が `selectedId` を `null` にする |

モーダルは `role="dialog"` と `aria-modal="true"` を付け、見出し「問い合わせ詳細」を `aria-labelledby` で結びつける。

### 8.7 ドラッグ&ドロップ

`@hello-pangea/dnd`（[技術スタック](tech-stack.md) 4.）を使う。置き場所と設定はタスク管理アプリと同じ。

| 部品 | 置く場所 | 設定 |
| --- | --- | --- |
| `DragDropContext` | `Board`。3 列すべてを包む | `onDragEnd={handleDragEnd}` |
| `Droppable` | `BoardList` の一覧の領域 | `droppableId={list.id}`。子の末尾に `provided.placeholder` を必ず置く |
| `Draggable` | `InquiryCard` | `draggableId={String(inquiry.id)}`（文字列であること）、`index` は列内の順番 |

- 挿入位置の表示（FR-04）は、ライブラリが他のカードをずらして隙間を作ることで満たす。モックの点線のプレースホルダーは使わない。
- `dragEndToMove(result)` は、`destination` が無いか、`source` と同じ列・同じ `index` なら `null`。それ以外は `{ id: Number(draggableId), listId: destination.droppableId, displayOrder: destination.index }` を返す。`destination.index` は「自分を除いた並びでの位置」で、API 設計書 10. の `displayOrder` と同じ定義なので、そのまま送れる。
- このライブラリはブラウザでだけ動く。`Board` がクライアントコンポーネントであり、静的書き出しの HTML には一覧の中身を含めない（取得前は「読み込み中…」）ため、サーバーでの描画との食い違いは起きない。
- 「完了」列へ動かした問い合わせは、`isOverdue` が `listId !== 'closed'` を見ているため、期限を過ぎていても強調が自動で消える。

### 8.8 ツールバーと「優先度順に並べ替え」

| 項目 | 内容 |
| --- | --- |
| 位置 | ヘッダーの直下、3 列のボードの上。リストの枠の外 |
| ボタン | 「優先度順に並べ替え」。白背景・青枠（`#0052cc`）・青文字・太字。hover で薄い青（`#deebff`） |
| 押したとき | `onSort` を呼ぶ。終わるまでボタンを無効にし、文言を「並べ替え中…」にする |
| 確認 | 求めない（[要件定義書](requirements.md) 決定事項 No.16） |
| 失敗 | `Board` が上部に「並べ替えを保存できませんでした。＋ 6.3 の文言」を表示する |

ボタンの横に説明文は置かない（モックの注記は、モックであることの説明を兼ねたもの）。ボードの上部の文言（`actionError`）は「閉じる」で消え、次の操作が成功したときにも消える。

---

## 9. 開発サーバーとバックエンドの接続

| 項目 | 内容 |
| --- | --- |
| フロントエンドの URL | `http://localhost:3000`（Next.js の既定。`npm run dev`） |
| バックエンドの URL | `http://localhost:3001`（Docker Compose の Rails） |
| 接続方式 | フロントエンドが `NEXT_PUBLIC_API_BASE_URL`（`.env.development` の `http://localhost:3001`）を先頭に付けて、Rails を直接呼ぶ。Rails は送信元 `http://localhost:3000` からの呼び出しを CORS で許可する（[API 設計書](api-design.md) 2. 方針 10） |
| 起動順 | ① `docker compose up -d`（MySQL・Rails）→ ② `npm run dev`（Next.js） |

```
【開発】 ブラウザ (localhost:3000 の画面) ──GET http://localhost:3001/api/inquiries──▶ Rails (3001)
                                                           （CORS で許可）
【本番】 ブラウザ ──GET https://xxxx.cloudfront.net/api/inquiries──▶ CloudFront ──▶ nginx ──▶ Rails
                                                           （同じドメインのため CORS は不要）
```

タスク管理アプリは Vite のプロキシで同じドメインに見せていたが、本プロジェクトは静的書き出しのため Next.js の転送（`rewrites`）が本番で使えない。開発と本番で仕組みを変えないよう、開発時もブラウザから API を直接呼ぶ（[技術スタック](tech-stack.md) 8. No.2）。

---

## 10. 設計上の決定事項

| No | 決定内容 | 関連 | タスク管理アプリとの違い | 決定日 |
| --- | --- | --- | --- | --- |
| 1 | App Router で 1 ページだけを作り、`output: 'export'` で静的ファイルに書き出す。ボードはクライアントコンポーネントとし、サーバーでだけ動く機能は使わない | 2.、3. | **異なる**（Vite + React） | 2026-10-31 |
| 2 | API の URL の先頭を `NEXT_PUBLIC_API_BASE_URL` で切り替え、開発時は Rails を直接呼ぶ（CORS） | 2.、9. | **異なる**（Vite のプロキシ） | 2026-10-31 |
| 3 | 状態管理ライブラリは導入せず、`useBoard` フックが保持する | 2.、5. | 同じ | 2026-10-31 |
| 4 | スタイルは CSS Modules とし、画面モックの CSS をコンポーネントごとに分割して移植する | 2.、3. | 同じ | 2026-10-31 |
| 5 | リストと問い合わせは同時に取得し、フロントエンドでは並べ替えず `listId` で振り分けるだけとする | 5.1 | 同じ | 2026-10-31 |
| 6 | API のエラーは `ApiError` 1 種類に正規化する。404 は「ほかのメンバーによって削除された」として扱い、全件を取り直す | 5.2、6. | 404 の扱いは新規 | 2026-10-31 |
| 7 | 書き込みに成功したら、影響を受けたリストを取り直して置き換える。ドラッグ&ドロップだけは楽観更新する | 2.、5. | 同じ | 2026-10-31 |
| 8 | 登録フォームは「未対応」列にだけ置く。必須の 3 項目に空があれば送らず、赤枠と項目名の文言で示す | 8.5 | **異なる**（全列に置き、空のタイトルは文言なしで無視） | 2026-10-31 |
| 9 | 問い合わせ詳細は「保存」ボタンを置かず、項目ごとに確定したときに **その項目だけ** を `PATCH` で送る。変更が無ければ送らない | 8.6 | **異なる**（4 項目をまとめて `PUT`） | 2026-10-31 |
| 10 | 問い合わせ詳細を開くときは、`GET /api/inquiries/{id}` で最新の 1 件を取得してから開く | 5.4 | **異なる**（手元の一覧から開き、API は呼ばない） | 2026-10-31 |
| 11 | 問い合わせ詳細でステータスを選び直したら、`PUT .../position` を `displayOrder` なしで呼ぶ（移動先の末尾）。楽観更新はしない | 5.6 | 新規 | 2026-10-31 |
| 12 | 削除は `window.confirm` の確認ダイアログを経て行う。楽観更新はしない | 5.8、8.6 | **異なる**（確認なし） | 2026-10-31 |
| 13 | 期限超過の判定はクライアントで描画のたびに行い、「完了」列のものは強調しない | 8.3 | 同じ | 2026-10-31 |
| 14 | ほかのメンバーの変更を自動で画面に反映する仕組み（定期的な取り直しなど）は設けない | 5.1 | 新規（要件定義書 決定事項 No.17） | 2026-10-31 |

---

## 11. 保留事項

| 事項 | 保留理由 | 決定時期 |
| --- | --- | --- |
| ほかのメンバーの変更の自動反映（一定時間ごとの取り直し、画面に戻ったときの取り直しなど） | 要件定義書 決定事項 No.17 で「画面を開き直したときに反映」とした。使ってみて不便が分かったら検討する | 不便が分かったとき |
| 通信エラー時の再試行の仕組み | 登録・編集の失敗は入力内容を残すので、もう一度確定すれば再送できる。移動の失敗は元に戻るので、もう一度ドラッグすればよい | 不便が分かったとき |
| ドラッグ&ドロップ操作の自動テスト | jsdom で再現しにくい。並びの計算（`applyMove`）とドロップ結果の判定（`dragEndToMove`）を純粋関数にして単体テストで確かめ、ドラッグ操作そのものはブラウザで手動確認する | ブラウザを使う自動テスト（Playwright など）を導入するとき |
| コード検査の具体的な構成（ESLint の設定など） | `create-next-app` の雛形に従うため | 雛形の作成時（技術スタックを更新する） |
