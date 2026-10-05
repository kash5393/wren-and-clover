interface FormFieldProps {
  id: string;
  label: string;
  value: string;
  onChange: (value: string) => void;
  error?: string;
  type?: string;
  multiline?: boolean;
  options?: string[];
}

function FormField({
  id,
  label,
  value,
  onChange,
  error,
  type = "text",
  multiline = false,
  options,
}: FormFieldProps) {
  const invalid = error ? true : undefined;
  let control;

  if (options) {
    control = (
      <select
        id={id}
        value={value}
        aria-invalid={invalid}
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
        rows={6}
        value={value}
        aria-invalid={invalid}
        onChange={(event) => onChange(event.target.value)}
      />
    );
  } else {
    control = (
      <input
        id={id}
        type={type}
        value={value}
        aria-invalid={invalid}
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

export default FormField;
