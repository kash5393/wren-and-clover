import "server-only";
import nodemailer from "nodemailer";
import type { OrderReceipt } from "./orders";

export interface Email {
  to: string;
  subject: string;
  text: string;
}

export async function sendEmail(email: Email): Promise<void> {
  const smtpUrl = process.env.SMTP_URL;
  const from = process.env.EMAIL_FROM ?? "Wren & Clover <orders@wrenandclover.test>";

  if (!smtpUrl) {
    console.log(
      [
        "",
        "----- Email preview (not sent: SMTP_URL is not set) -----",
        `From: ${from}`,
        `To: ${email.to}`,
        `Subject: ${email.subject}`,
        "",
        email.text,
        "--------------------------------------------------------",
        "",
      ].join("\n")
    );
    return;
  }

  const transport = nodemailer.createTransport(smtpUrl);
  await transport.sendMail({ from, ...email });
}

function describeLines(order: OrderReceipt): string {
  return order.lines
    .map((line) => `  ${line.quantity} x ${line.name} (${line.scent})  $${line.unitPrice * line.quantity}`)
    .join("\n");
}

export async function sendOrderEmails(order: OrderReceipt): Promise<void> {
  const emails: Email[] = [
    {
      to: order.email,
      subject: `Your Wren & Clover order ${order.orderNumber}`,
      text: [
        `Hi ${order.customerName},`,
        "",
        `Thank you for your order ${order.orderNumber}.`,
        "",
        describeLines(order),
        "",
        `Total: $${order.total}`,
        "",
        `Shipping to: ${order.address}`,
        "",
        "We'll pack it within two working days.",
        "",
        "Wren & Clover Botanicals",
      ].join("\n"),
    },
  ];

  const ownerEmail = process.env.OWNER_EMAIL;
  if (ownerEmail) {
    emails.push({
      to: ownerEmail,
      subject: `New order ${order.orderNumber} ($${order.total})`,
      text: [
        `${order.customerName} <${order.email}> placed order ${order.orderNumber}.`,
        "",
        describeLines(order),
        "",
        `Total: $${order.total}`,
        `Ship to: ${order.address}`,
      ].join("\n"),
    });
  }

  for (const email of emails) {
    try {
      await sendEmail(email);
    } catch (error) {
      console.error(`Could not send email to ${email.to}:`, error);
    }
  }
}
