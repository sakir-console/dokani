# Dokani mobile app

Flutter app for shop owners. Bangla by default, English available.

Setup, run and test instructions: [`../docs/06-setup.md`](../docs/06-setup.md).
Structure: [`../docs/04-project-structure.md`](../docs/04-project-structure.md).

## Layout

```
lib/
  app/         MaterialApp, router, theme
  core/        API client, storage, validators, shared widgets
  features/    one folder per feature: data / application / presentation
  l10n/        app_bn.arb, app_en.arb (all user-facing text lives here)
```

## Rules for anyone adding code here

1. Screens never call Dio. They call a repository, which converts failures to `ApiException`.
2. All user-facing text goes in both `.arb` files. No hard-coded strings in widgets.
3. Hiding a button because of a role or plan is a convenience only; the server enforces it.
4. A submit button uses `PrimaryButton` with `busy`, so a slow network cannot cause a double submit.
