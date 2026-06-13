# Common Platform Release Notes v1

## Status

KM Auth Starter common platform v1 is ready for product fork.

## Included

### Auth

- Signup
- Login / logout
- Current user
- Email verification
- Password reset
- Cookie session
- CSRF protection

### Onboarding

- User profile
- Terms acceptance
- Privacy acceptance
- App membership start
- Dashboard entry

### Billing

- Credit products
- Checkout Session creation
- Stripe Checkout
- Stripe Webhook
- Credit balance
- Credit transactions

### Mail

- File delivery for local fallback
- Resend delivery
- Custom Resend delivery method
- Solid Queue mail jobs
- Resend Webhook
- Email webhook events
- Email suppression

### Operations

- `/up`
- `/healthz`
- `/readiness`
- `bin/rails km:doctor`
- development cleanup tasks

### Admin API

- Users
- Audit logs
- Billing history
- Stripe webhook events
- Email webhook events
- Email suppressions

### Tests

- Rails tests
- Vitest tests
- Admin API test
- Stripe webhook test
- Mailer tests

## Not Included

- Product-specific UI
- Hodokoo AI/OCR/checker functionality
- Coconique matching functionality
- Coconique identity verification
- Full admin dashboard UI
- Production infrastructure IaC

## Known Notes

- Resend standard ActionMailer adapter may pass `from` / `to` as arrays in this environment. Use `ResendDeliveryMethod`.
- `delivery_method` must be `resend_custom` when `MAIL_PROVIDER=resend`.
- `app/lib` must be included in handoff zip.
- Webhook endpoints must live outside `/api/v1`.
- `localhost` URLs in email bodies can cause spam classification during tests.

## Final Verified Flow

- `deliver_now` with Resend: OK
- `deliver_later` with Solid Queue + Resend: OK
- Resend Logs 200: OK
- Email delivered: OK
- Resend Webhook `email.sent`: OK
- Resend Webhook `email.delivered`: OK
- Readiness: OK
- km:doctor: OK
- Admin API: OK
