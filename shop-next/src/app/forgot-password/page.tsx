import type { Metadata } from "next";
import ForgotPasswordForm from "@/components/ForgotPasswordForm";

export const metadata: Metadata = {
  title: "Forgot password",
};

export default function ForgotPasswordPage() {
  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Forgot your password?</h1>
        <ForgotPasswordForm />
      </div>
    </section>
  );
}
