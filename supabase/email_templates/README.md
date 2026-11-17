# Plantillas OTP de correo

Estas plantillas son para **Supabase Auth** (el proyecto usa Supabase, no Firebase). Copia el contenido HTML del archivo correspondiente en Authentication → Email Templates:

- `confirm_signup.html`: plantilla **Confirm signup**. Asunto sugerido: `Confirma tu correo · V&S Inversiones`.
- `reset_password.html`: plantilla **Reset password**. Asunto sugerido: `Código para restablecer tu contraseña · V&S Inversiones`.

Ambas usan `{{ .Token }}` para mostrar el OTP y están pensadas para que el usuario lo escriba en la aplicación. No reemplaces esa variable por `{{ .ConfirmationURL }}` si quieres enviar un código en lugar de un enlace.

El símbolo vectorial original está embebido en el HTML y no requiere alojar un archivo. Algunos clientes de correo pueden quitar SVG; por eso el encabezado incluye también el nombre `P3L1CO` como texto HTML. Si el símbolo no aparece en un cliente concreto, el nombre de marca seguirá visible y el código seguirá funcionando.
