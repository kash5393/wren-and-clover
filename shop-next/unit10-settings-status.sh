#!/usr/bin/env bash
# Settings page: green status badges and clearer success and error messages.
# Run from inside the shop-next folder:  bash unit10-settings-status.sh
set -e
if [ ! -f src/components/SettingsForm.tsx ]; then echo "Run this inside the shop-next folder, after the settings step."; exit 1; fi
cat > src/components/SettingsForm.tsx << 'WREN_EOF'
"use client";

import { useActionState } from "react";
import {
  clearSettingAction,
  saveSettingsAction,
  testEmailAction,
  testStripeAction,
} from "@/app/admin/actions";
import type { SettingsFormState } from "@/app/admin/actions";
import type { SettingKey, SettingStatus } from "@/lib/settings";

interface SettingsFormProps {
  statuses: Record<SettingKey, SettingStatus>;
  webhookUrl: string;
  canSave: boolean;
}

const initialState: SettingsFormState = { error: "", message: "" };

const sourceLabels = {
  admin: "Saved here",
  environment: "Set in the hosting settings",
  none: "Not set",
};

function Feedback({ state }: { state: SettingsFormState }) {
  return (
    <>
      {state.error && (
        <p className="notice notice-error" role="alert">
          <span aria-hidden="true">✕</span> {state.error}
        </p>
      )}
      {state.message && (
        <p className="notice notice-success" role="status">
          <span aria-hidden="true">✓</span> {state.message}
        </p>
      )}
    </>
  );
}

function Badge({ ok, okText, offText }: { ok: boolean; okText: string; offText: string }) {
  return (
    <span className={ok ? "status-badge status-on" : "status-badge status-off"}>
      <span aria-hidden="true">{ok ? "✓" : "○"}</span> {ok ? okText : offText}
    </span>
  );
}

function Current({ id, status }: { id: SettingKey; status: SettingStatus }) {
  const isSet = status.source !== "none";

  return (
    <p className="setting-current">
      <Badge ok={isSet} okText={sourceLabels[status.source]} offText="Not set" />
      {status.display && <span className="setting-value">{status.display}</span>}
      {status.source === "admin" && (
        <button className="link-button" type="submit" form={`clear-${id}`}>
          Remove
        </button>
      )}
    </p>
  );
}

export default function SettingsForm({ statuses, webhookUrl, canSave }: SettingsFormProps) {
  const [saveState, saveAction, saving] = useActionState(saveSettingsAction, initialState);
  const [stripeState, stripeAction, testingStripe] = useActionState(testStripeAction, initialState);
  const [emailState, emailAction, testingEmail] = useActionState(testEmailAction, initialState);

  const fields: { id: SettingKey; label: string; secret: boolean; placeholder: string }[] = [
    { id: "stripeSecretKey", label: "Stripe secret key", secret: true, placeholder: "sk_test_..." },
    {
      id: "stripeWebhookSecret",
      label: "Stripe webhook signing secret",
      secret: true,
      placeholder: "whsec_...",
    },
    {
      id: "smtpUrl",
      label: "Email server address",
      secret: true,
      placeholder: "smtps://user:password@smtp.example.com:465",
    },
    {
      id: "emailFrom",
      label: "Emails are sent from",
      secret: false,
      placeholder: "Wren & Clover <orders@yourdomain.com>",
    },
    { id: "siteUrl", label: "Site address", secret: false, placeholder: "https://yourshop.com" },
  ];

  const isSet = (key: SettingKey) => statuses[key].source !== "none";

  const sections: {
    title: string;
    intro: string;
    keys: SettingKey[];
    ready: boolean;
    onText: string;
    offText: string;
  }[] = [
    {
      title: "Payments",
      intro:
        "With a Stripe secret key, checkout sends customers to Stripe's payment page. Without one, orders complete without payment.",
      keys: ["stripeSecretKey"],
      ready: isSet("stripeSecretKey"),
      onText: "Payments are on",
      offText: "Payments are off",
    },
    {
      title: "Webhook",
      intro:
        "A webhook lets Stripe tell the shop about a payment even if the customer closes the page before returning.",
      keys: ["stripeWebhookSecret"],
      ready: isSet("stripeWebhookSecret"),
      onText: "Webhook connected",
      offText: "Webhook not connected",
    },
    {
      title: "Email",
      intro:
        "With an email server, order confirmations and password resets are really sent. Without one, they are only written to the server log.",
      keys: ["smtpUrl", "emailFrom"],
      ready: isSet("smtpUrl"),
      onText: "Emails are being sent",
      offText: "Emails are not being sent",
    },
    {
      title: "Site",
      intro: "The public address of the shop, used in payment and email links.",
      keys: ["siteUrl"],
      ready: isSet("siteUrl"),
      onText: "Address set",
      offText: "Using the default address",
    },
  ];

  return (
    <>
      {fields.map((field) => (
        <form key={field.id} id={`clear-${field.id}`} action={clearSettingAction}>
          <input type="hidden" name="key" value={field.id} />
        </form>
      ))}

      <form className="settings-form" action={saveAction}>
        {sections.map((section) => (
          <section
            className={section.ready ? "settings-section settings-ready" : "settings-section"}
            key={section.title}
          >
            <div className="settings-heading">
              <h2>{section.title}</h2>
              <Badge ok={section.ready} okText={section.onText} offText={section.offText} />
            </div>
            <p>{section.intro}</p>

            {section.title === "Webhook" && (
              <div className="setting-help">
                <p>
                  In Stripe, add a webhook endpoint with this address, and choose the events{" "}
                  <code>checkout.session.completed</code>,{" "}
                  <code>checkout.session.async_payment_succeeded</code> and{" "}
                  <code>checkout.session.expired</code>:
                </p>
                <p>
                  <code>{webhookUrl}</code>
                </p>
              </div>
            )}

            {section.keys.map((key) => {
              const field = fields.find((item) => item.id === key);
              if (!field) {
                return null;
              }
              return (
                <div className="field" key={field.id}>
                  <label htmlFor={field.id}>{field.label}</label>
                  <Current id={field.id} status={statuses[field.id]} />
                  <input
                    id={field.id}
                    name={field.id}
                    type={field.secret ? "password" : "text"}
                    autoComplete="off"
                    placeholder={field.placeholder}
                    disabled={!canSave}
                  />
                </div>
              );
            })}
          </section>
        ))}

        <p className="setting-help">Leave a box empty to keep its current value.</p>
        <Feedback state={saveState} />
        <div className="cart-actions">
          <button className="button" type="submit" disabled={!canSave || saving}>
            {saving ? "Saving..." : "Save settings"}
          </button>
        </div>
      </form>

      <section className="settings-section">
        <h2>Check that it works</h2>
        <div className="cart-actions">
          <form action={stripeAction}>
            <button className="button" type="submit" disabled={testingStripe}>
              {testingStripe ? "Checking..." : "Test Stripe connection"}
            </button>
          </form>
          <form action={emailAction}>
            <button className="button" type="submit" disabled={testingEmail}>
              {testingEmail ? "Sending..." : "Send a test email"}
            </button>
          </form>
        </div>
        <Feedback state={stripeState} />
        <Feedback state={emailState} />
      </section>
    </>
  );
}
WREN_EOF

grep -q "status-badge" src/app/globals.css || cat >> src/app/globals.css << 'WREN_EOF'

/* Settings status colours */
.settings-heading {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-1);
}

.settings-ready {
  border-color: #7fbf8e;
  border-left: 6px solid #2e7d46;
}

.status-badge {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  padding: 0.2rem 0.65rem;
  font-size: 0.85rem;
  font-weight: 600;
  border-radius: 999px;
}

.status-on {
  color: #17592d;
  background: #dff3e4;
  border: 1px solid #7fbf8e;
}

.status-off {
  color: #55554c;
  background: #efede6;
  border: 1px solid #cfcabb;
}

.setting-current {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-1);
}

.setting-value {
  color: var(--color-text);
  font-family: ui-monospace, monospace;
  overflow-wrap: anywhere;
}

.setting-help {
  margin: 0;
  color: var(--color-muted);
  font-size: 0.9rem;
}

.notice {
  margin: 0;
  padding: 0.75rem 1rem;
  font-weight: 600;
  border-radius: var(--radius);
}

.notice-success {
  color: #17592d;
  background: #dff3e4;
  border: 1px solid #7fbf8e;
}

.notice-error {
  color: #8c1d18;
  background: #fbe4e2;
  border: 1px solid #e3a09b;
}
WREN_EOF

echo "Done. The dev server picks the changes up by itself."
