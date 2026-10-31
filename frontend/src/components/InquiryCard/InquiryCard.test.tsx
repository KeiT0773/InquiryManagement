import { DragDropContext, Droppable } from '@hello-pangea/dnd';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { makeInquiry } from '@/test/fixtures';
import type { Inquiry } from '@/types/inquiry';
import { InquiryCard } from './InquiryCard';

// Draggable は DragDropContext と Droppable の中でしか描画できない
function renderCard(inquiry: Inquiry, onClick = vi.fn()) {
  render(
    <DragDropContext onDragEnd={() => undefined}>
      <Droppable droppableId={inquiry.listId}>
        {(provided) => (
          <div ref={provided.innerRef} {...provided.droppableProps}>
            <InquiryCard inquiry={inquiry} index={0} onClick={onClick} />
            {provided.placeholder}
          </div>
        )}
      </Droppable>
    </DragDropContext>,
  );
  return onClick;
}

afterEach(() => {
  vi.useRealTimers();
});

describe('InquiryCard', () => {
  it('優先度・件名・問い合わせ者（様付き）・対応者・種別・期限を表示する', () => {
    vi.useFakeTimers({ now: new Date(2026, 9, 31), toFake: ['Date'] });
    renderCard(
      makeInquiry(1, 'open', 0, {
        title: 'ログインできない',
        customerName: '山田 太郎',
        assignee: '小林',
        priority: 'high',
        category: 'bug',
        dueOn: '2026-11-01',
      }),
    );

    expect(screen.getByText('高')).toBeInTheDocument();
    expect(screen.getByText('ログインできない')).toBeInTheDocument();
    expect(screen.getByText('山田 太郎 様')).toBeInTheDocument();
    expect(screen.getByText('対応者 小林')).toBeInTheDocument();
    expect(screen.getByText('不具合')).toBeInTheDocument();
    expect(screen.getByText('期限 11/01')).toBeInTheDocument();
  });

  it('対応者が未割当なら「対応者 未割当」を強調する', () => {
    renderCard(makeInquiry(1, 'open', 0, { assignee: null }));

    expect(screen.getByText('対応者 未割当').className).toMatch(/unassigned/);
  });

  it('期限を過ぎたものは「期限切れ」を付けて強調する。完了にあるものは強調しない', () => {
    vi.useFakeTimers({ now: new Date(2026, 10, 1), toFake: ['Date'] });
    renderCard(makeInquiry(1, 'working', 0, { dueOn: '2026-10-31' }));
    expect(screen.getByText('期限 10/31（期限切れ）').className).toMatch(/overdue/);

    renderCard(makeInquiry(2, 'closed', 0, { dueOn: '2026-10-31' }));
    expect(screen.getByText('期限 10/31').className).not.toMatch(/overdue/);
  });

  it('クリックまたは Enter で onClick を呼ぶ', async () => {
    const user = userEvent.setup();
    const onClick = renderCard(makeInquiry(1, 'open', 0, { title: 'ログインできない' }));

    await user.click(screen.getByText('ログインできない'));
    screen.getByRole('button').focus();
    await user.keyboard('{Enter}');

    expect(onClick).toHaveBeenCalledTimes(2);
  });
});
