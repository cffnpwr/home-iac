import cffnpwrConfig from "@cffnpwr/eslint-config";
import tsEslintParser from "@typescript-eslint/parser";
import { defineConfig } from "eslint/config";
import globals from "globals";

const files = ["**/*.{js,ts}"];

export default defineConfig([
  {
    files,
    languageOptions: {
      globals: {
        ...globals.bunBuiltin,
      },
      parser: tsEslintParser,
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
  },
  {
    files,
    extends: cffnpwrConfig(),
  },
]);
