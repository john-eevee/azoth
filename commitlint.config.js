export default {
  extends: ["@commitlint/config-conventional"],
  rules: {
    "scope-enum": [2, "always", ["atnr", "qksv", "docs", "infra"]]
  }
};
