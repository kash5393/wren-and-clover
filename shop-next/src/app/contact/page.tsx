import type { Metadata } from "next";
import ContactForm from "./ContactForm";

export const metadata: Metadata = {
  title: "Contact",
};

export default function ContactPage() {
  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Contact</h1>
        <p>
          Questions about an order or an ingredient? Send a message and
          we&apos;ll reply within two working days.
        </p>
        <ContactForm />
      </div>
    </section>
  );
}
