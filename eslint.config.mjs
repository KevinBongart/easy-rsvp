import js from "@eslint/js"
import globals from "globals"

export default [
  {
    files: ["app/javascript/**/*.js"],
    ...js.configs.recommended,
    languageOptions: {
      globals: globals.browser,
      sourceType: "module"
    }
  }
]
