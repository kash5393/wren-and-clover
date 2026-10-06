#!/usr/bin/env bash
# Unit 9, step 3: automatic checks on every push, and the Stripe webhook.
# Run from the wren-and-clover project folder:  bash unit9-ci.sh
set -e
if [ ! -f shop-next/src/lib/payments.ts ] || [ ! -f shop-next/vitest.config.ts ]; then echo "Run this inside the wren-and-clover folder, after the tests step."; exit 1; fi
mkdir -p .github/workflows shop-next/src/app/api/stripe/webhook

cat > .github/workflows/ci.yml << 'WREN_EOF'
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  shop-next:
    name: Lint, test and build the shop
    runs-on: ubuntu-latest

    defaults:
      run:
        working-directory: shop-next

    env:
      # A placeholder so the build can load the database module. Nothing connects to it.
      DATABASE_URL: postgresql://ci:ci@localhost:5432/ci

    steps:
      - name: Check out the code
        uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
          cache-dependency-path: shop-next/package-lock.json

      - name: Install packages
        run: npm ci

      - name: Lint
        run: npm run lint

      - name: Run tests
        run: npm test

      - name: Build
        run: npm run build
WREN_EOF

cat > shop-next/src/app/api/stripe/webhook/route.ts << 'WREN_EOF'
import { sendOrderEmails } from "@/lib/email";
import { cancelPendingOrder, getReceiptBySession, markOrderPaid } from "@/lib/orders";
import { getStripe, paymentsEnabled } from "@/lib/payments";

export async function POST(request: Request): Promise<Response> {
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!webhookSecret || !paymentsEnabled()) {
    return new Response("Webhook is not configured", { status: 400 });
  }

  const signature = request.headers.get("stripe-signature") ?? "";
  const body = await request.text();

  let event;
  try {
    event = getStripe().webhooks.constructEvent(body, signature, webhookSecret);
  } catch {
    return new Response("Invalid signature", { status: 400 });
  }

  if (
    event.type === "checkout.session.completed" ||
    event.type === "checkout.session.async_payment_succeeded"
  ) {
    const session = event.data.object;

    if (session.payment_status === "paid") {
      const order = await getReceiptBySession(session.id);

      if (order && order.status === "pending") {
        const firstTime = await markOrderPaid(order.id);
        if (firstTime) {
          console.log(`Order ${order.orderNumber} paid (confirmed by Stripe webhook)`);
          await sendOrderEmails(order);
        }
      }
    }
  }

  if (event.type === "checkout.session.expired") {
    const order = await getReceiptBySession(event.data.object.id);

    if (order && order.status === "pending") {
      await cancelPendingOrder(order.id);
      console.log(`Order ${order.orderNumber} cancelled: its payment page expired`);
    }
  }

  return Response.json({ received: true });
}
WREN_EOF

grep -q 'STRIPE_WEBHOOK_SECRET' shop-next/.env.local 2>/dev/null || cat >> shop-next/.env.local << 'WREN_EOF'

# Stripe webhook signing secret (starts with whsec_). Only needed where Stripe can reach the site.
#STRIPE_WEBHOOK_SECRET=
WREN_EOF

echo "Checking the shop the same way GitHub will..."
(cd shop-next && npm run lint && npm test && npm run build)
echo
echo "Done. Commit and push to see the checks run on GitHub."
