# Counts failed HTTP Basic sign-ins to the admin dashboard per client. Only
# failures count, so the administrator's own use is never limited. Past LIMIT
# failures within WINDOW, the client gets 429 for every admin request,
# including ones with the right password, until the window passes: answering
# a correct guess differently would keep the guessing useful.
#
# A per-client limit cannot stop guessing spread over many addresses (a proxy
# pool gets LIMIT tries per address per WINDOW), so ADMIN_PASSWORD must be a
# long random secret. Failures are also counted site-wide, and reaching
# SITE_WIDE_ALERT within WINDOW reports to Honeybadger once so such an attack
# gets noticed. The site-wide count never refuses anyone: that would let any
# attacker lock the administrator out.
class AdminSignInFailures
  # One person signs in here; a password manager or a few typos stay far
  # below this, while guessing slows to LIMIT tries per WINDOW per address.
  LIMIT = 10
  WINDOW = 1.hour
  # Five clients' worth of failures: more than the administrator's own
  # devices could produce.
  SITE_WIDE_ALERT = 50
  SITE_WIDE_KEY = "admin-sign-in-failures:all"

  def initialize(client_digest)
    @key = "admin-sign-in-failures:#{client_digest}"
  end

  def too_many?
    ClientRequestCounts::STORE.read(@key).to_i >= LIMIT
  end

  # The counters' windows start with the first failure and are not extended
  # by later ones.
  def record
    ClientRequestCounts::STORE.increment(@key, 1, expires_in: WINDOW)
    site_wide = ClientRequestCounts::STORE.increment(SITE_WIDE_KEY, 1, expires_in: WINDOW)
    report_distributed_guessing if site_wide == SITE_WIDE_ALERT
  end

  private

  def report_distributed_guessing
    Honeybadger.notify("#{SITE_WIDE_ALERT} failed admin sign-ins within #{WINDOW.inspect}",
      error_class: "AdminSignInFailures::DistributedGuessing")
  end
end
