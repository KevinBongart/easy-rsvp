# Records every Content-Security-Policy violation the browser reports, from
# the first byte of each document, including violations that break nothing
# visible. Violations are kept in sessionStorage so they survive full page
# loads as well as Turbo visits within the same tab.
module CspViolations
  RECORDER = <<~JS
    () => {
      document.addEventListener("securitypolicyviolation", (event) => {
        const violations = JSON.parse(sessionStorage.getItem("cspViolations") || "[]")
        violations.push({
          page: document.location.pathname,
          directive: event.effectiveDirective,
          blocked: event.blockedURI,
          sample: event.sample
        })
        sessionStorage.setItem("cspViolations", JSON.stringify(violations))
      }, true)
    }
  JS

  def record_csp_violations
    page.driver.browser.bidi.send_cmd("script.addPreloadScript", functionDeclaration: RECORDER)
  end

  def csp_violations
    JSON.parse(page.evaluate_script('sessionStorage.getItem("cspViolations") || "[]"'))
  end
end

RSpec.configure do |config|
  config.include CspViolations, type: :system
end
