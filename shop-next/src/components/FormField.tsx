interface FormFieldProps {
  id: string;
  label: string;
  value: string;
  onChange: (value: string) => void;
  error?: string;
  type?: string;
  multiline?: boolean;
  options?: string[];
  autoComplete?: string;
}

export default function FormField({
  id,
  label,
  value,
  onChange,
  error,
  type = "text",
  multiline = false,
  options,
  autoComplete,
}: FormFieldProps) {
  const invalid = error ? true : undefined;
  let control;

  if (options) {
    control = (
      <select
        id={id}
        name={id}
        value={value}
        aria-invalid={invalid}
        autoComplete={autoComplete}
        onChange={(event) => onChange(event.target.value)}
      >
        <option value="">Select...</option>
        {options.map((option) => (
          <option key={option} value={option}>
            {option}
          </option>
        ))}
      </select>
    );
  } else if (multiline) {
    control = (
      <textarea
        id={id}
        name={id}
        rows={6}
        value={value}
        aria-invalid={invalid}
        autoComplete={autoComplete}
        onChange={(event) => onChange(event.target.value)}
      />
    );
  } else {
    control = (
      <input
        id={id}
        name={id}
        type={type}
        value={value}
        aria-invalid={invalid}
        autoComplete={autoComplete}
        onChange={(event) => onChange(event.target.value)}
      />
    );
  }

  return (
    <div className="field">
      <label htmlFor={id}>{label}</label>
      {control}
      {error && <span className="field-error">{error}</span>}
    </div>
  );
}
