import type { Withdrawal, WithdrawalReason } from '../domain/types';
import { Icon } from './Icon';

/**
 * A pattern that stopped qualifying, and why (A2).
 *
 * The point of this component is that a withdrawal is an *event*, not an absence. Before it
 * existed, a pattern the user had read and acted on could disappear between two visits with nothing
 * said, which is indistinguishable from the app having been wrong the first time. Here it is a
 * card, with the previous count, the new one, and a reason drawn from a fixed set the backend
 * decides (A2-02) — never a sentence a model wrote.
 *
 * Every word and number below arrives in the payload. This file chooses the icon and the layout.
 */

/**
 * Presentation only. The reason itself is the backend's, and there are four of them.
 *
 * Each label names the thing that actually changed, which is only possible because the codes
 * distinguish them: "Not enough left" beside a count of 12 → 12 would be false, and that is exactly
 * what a single `below_threshold` covering both cases forced this badge to say.
 */
const REASON_LABEL: Record<WithdrawalReason, string> = {
  below_threshold: 'Not enough left',
  below_lift: 'Association too weak',
  no_longer_confirmed: 'No confirmed feelings',
  topic_merged: 'Topic merged',
};

export function WithdrawalNotice({ withdrawal }: { withdrawal: Withdrawal }) {
  return (
    <li
      className={`withdrawal ${withdrawal.is_new ? 'withdrawal--new' : ''}`}
      aria-label={`Withdrawn: ${withdrawal.topic}`}
    >
      <span className="withdrawal__icon" aria-hidden="true">
        <Icon name="clock" size="1.05em" />
      </span>
      <div className="withdrawal__body">
        <p className="withdrawal__head">
          {/*
            An inverse pattern was a claim about the entries that did *not* mention the topic, and
            the heading has to say so or it reads as the forward pattern going away instead.
          */}
          <strong className="withdrawal__topic">
            {withdrawal.kind === 'inverse' ? `Without ${withdrawal.topic}` : withdrawal.topic}
          </strong>
          <span className="muted"> → {withdrawal.feeling}</span>
          <span className="withdrawal__reason">
            {REASON_LABEL[withdrawal.reason] ?? withdrawal.reason}
          </span>
        </p>
        <p className="withdrawal__detail">{withdrawal.detail_text}</p>
        <p className="withdrawal__counts muted tnum">
          {withdrawal.previous_count} → {withdrawal.new_count}
        </p>
      </div>
    </li>
  );
}
