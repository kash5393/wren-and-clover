import { describe, expect, it } from "vitest";
import { emptyCheckoutForm, validateCheckout } from "./checkout-validation";
import type { CheckoutFields } from "./checkout-validation";

const validForm: CheckoutFields = {
  name: "Ada Lovelace",
  email: "ada@example.com",
  phone: "401 555 0123",
  address: "1 Main Street",
  city: "Cranston",
  state: "RI",
  postcode: "02920",
};

describe("validateCheckout", () => {
  it("accepts a correctly filled form", () => {
    expect(validateCheckout(validForm)).toEqual({});
  });

  it("reports every field of an empty form", () => {
    const errors = validateCheckout(emptyCheckoutForm);

    expect(Object.keys(errors).sort()).toEqual(
      ["address", "city", "email", "name", "phone", "postcode", "state"]
    );
  });

  it("rejects an email without an @", () => {
    const errors = validateCheckout({ ...validForm, email: "ada.example.com" });

    expect(errors.email).toBe("Please enter a valid email address.");
  });

  it("rejects a phone number with letters", () => {
    expect(validateCheckout({ ...validForm, phone: "call me" }).phone).toBeDefined();
  });

  it("only accepts a known two-letter state", () => {
    expect(validateCheckout({ ...validForm, state: "Rhode Island" }).state).toBeDefined();
    expect(validateCheckout({ ...validForm, state: "ZZ" }).state).toBeDefined();
    expect(validateCheckout({ ...validForm, state: "CA" }).state).toBeUndefined();
  });

  it("accepts five-digit and nine-digit ZIP codes", () => {
    expect(validateCheckout({ ...validForm, postcode: "02920" }).postcode).toBeUndefined();
    expect(validateCheckout({ ...validForm, postcode: "02920-1234" }).postcode).toBeUndefined();
  });

  it("rejects a ZIP code of the wrong length", () => {
    expect(validateCheckout({ ...validForm, postcode: "2920" }).postcode).toBeDefined();
    expect(validateCheckout({ ...validForm, postcode: "029201" }).postcode).toBeDefined();
  });

  it("treats a name of only spaces as empty", () => {
    expect(validateCheckout({ ...validForm, name: "   " }).name).toBeDefined();
  });
});
