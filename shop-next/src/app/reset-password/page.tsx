import type { Metadata } from "next";
import Link from "next/link";
import ResetPasswordForm from "@/components/ResetPasswordForm";
import { isResetTokenValid } from "@/lib/password-reset";

export const metadata: Metadata = {
  title: "Choose a new password",
  robots: { index: false },
  referrer: "no-referrer",
};

export default async function ResetPasswordPage(props: PageProps<"/reset-password">) {
  const query = await props.searchParams;
  const token = typeof query.token === "string" ? query.token : "";
  const valid = await isResetTokenValid(token);

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Choose a new password</h1>

        {valid ? (
          <ResetPasswordForm token={token} />
        ) : (
          <>
            <p>This reset link has expired or was already used.</p>
            <Link className="button" href="/forgot-password">Request a new link</Link>
          </>
        )}
      </div>
    </section>
  );
}
