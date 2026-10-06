import type { Metadata } from "next";
import SettingsForm from "@/components/SettingsForm";
import { requireOwner } from "@/lib/auth";
import { siteUrl } from "@/lib/payments";
import { describeSettings, encryptionReady } from "@/lib/settings";

export const metadata: Metadata = {
  title: "Settings",
};

export default async function AdminSettingsPage() {
  await requireOwner();

  const statuses = await describeSettings();
  const canSave = encryptionReady();
  const webhookUrl = `${await siteUrl()}/api/stripe/webhook`;

  return (
    <div className="prose">
      <h1 className="page-title">Settings</h1>

      {!canSave && (
        <p className="field-error" role="alert">
          Settings can&apos;t be saved here yet. Add a SETTINGS_ENCRYPTION_KEY to the hosting
          settings first. It is the master key that keeps everything on this page encrypted.
        </p>
      )}

      <p>
        Keys saved here are encrypted before they are stored, and are never shown again in full.
        Only the last four characters are displayed.
      </p>

      <SettingsForm statuses={statuses} webhookUrl={webhookUrl} canSave={canSave} />
    </div>
  );
}
