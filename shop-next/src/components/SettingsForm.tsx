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
  environment: "From the hosting settings",
  none: "Not set",
};

function Feedback({ state }: { state: SettingsFormState }) {
  return (
    <>
      {state.error && (
        <p className="field-error" role="alert">
          {state.error}
        </p>
      )}
      {state.message && (
        <p className="form-status" role="status">
          {state.message}
        </p>
      )}
    </>
  );
}

function Current({ id, status }: { id: SettingKey; status: SettingStatus }) {
  return (
    <p className="setting-current">
      {sourceLabels[status.source]}
      {status.display && `: ${status.display}`}
      {status.source === "admin" && (
        <>
          {" "}
          <button className="link-button" type="submit" form={`clear-${id}`}>
            Remove
          </button>
        </>
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

  const sections: { title: string; intro: string; keys: SettingKey[] }[] = [
    {
      title: "Payments",
      intro:
        "With a Stripe secret key, checkout sends customers to Stripe's payment page. Without one, orders complete without payment.",
      keys: ["stripeSecretKey"],
    },
    {
      title: "Webhook",
      intro:
        "A webhook lets Stripe tell the shop about a payment even if the customer closes the page before returning.",
      keys: ["stripeWebhookSecret"],
    },
    {
      title: "Email",
      intro:
        "With an email server, order confirmations and password resets are really sent. Without one, they are only written to the server log.",
      keys: ["smtpUrl", "emailFrom"],
    },
    {
      title: "Site",
      intro: "The public address of the shop, used in payment and email links.",
      keys: ["siteUrl"],
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
          <section className="settings-section" key={section.title}>
            <h2>{section.title}</h2>
            <p>{section.intro}</p>

            {section.title === "Webhook" && (
              <div className="setting-current">
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

        <p className="setting-current">Leave a box empty to keep its current value.</p>
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
