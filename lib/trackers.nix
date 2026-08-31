#
# The household catalogue: what runs a HOUSEHOLD rather than a business or a workstation. Two
# groups, because the subject genuinely contains two kinds of workload and flattening them would
# make the model lie:
#
#   `trackers`    an application whose product IS a record that outlives every session with it --
#                 of the objects you own, of the stock you hold, or of the work that comes round.
#                 It is the thing a person opens, and it is authoritative for whatever it records.
#   `companions`  something that exists only to FEED a tracker. It keeps no record of its own,
#                 every action it takes lands in somebody else's database, and it is empty and
#                 pointless without the tracker it serves.
#
# THE PLACEMENT RULE, stated as a boundary rather than a list so the next candidate is decidable
# without an argument:
#
#   Does the thing keep the household's own record -- what is owned, what is held, what is due --
#   or feed something that does?
#     yes -> here
#     no  -> whichever repository owns the thing it actually is
#
# "A person uses it at home" is NOT the test, and that clause is load-bearing: almost every
# self-hosted application is used at home, and if location were the test this catalogue would
# swallow the whole application layer. A dashboard that links to these four is a page of links; a
# note-taker that happens to hold a shopping list is a note-taker. The test is whether the
# application is the HOUSEHOLD'S RECORD of something.
#
# ── THE TWO DOMAINS, AND THE RULE THAT SEPARATES THEM ──────────────────────────────────────────
#
# Every tracker names a `domain`, and the domain is knowledge rather than a preference: which of
# these two questions an application answers is a property of the software, true wherever it runs.
# It is also the one field that DECIDES something structural -- a workload's namespace comes from
# its domain (see ../modules/cluster.nix), so the split is load-bearing rather than decorative.
#
#   `belongings`    the record names a THING YOU KEEP: one durable object with its own identity,
#                   answering where it is, what it cost, and when its warranty or its next service
#                   falls due. Rows are created once and deleted once. Nothing about a belonging
#                   is a quantity.
#
#   `housekeeping`  the record names something that RUNS OUT OR COMES ROUND: a quantity that
#                   depletes and has to be restocked, or an obligation that recurs on a schedule.
#                   The row is not the point -- the level and the date are, and both move without
#                   anybody editing anything.
#
# THE TELL, when a candidate looks like both: does the record get CONSUMED? A drill is a belonging.
# The drill bits you use up are stock. "Sharpen the bits every spring" is a chore. Same shelf,
# three different records, and only the first one is still there in five years with the same
# identity.
#
# NEITHER DOMAIN IS NAMED AFTER AN APPLICATION IN IT, and that is a rule rather than a coincidence.
# A group named for one of its members reads as though that member were the group's definition,
# which is exactly the confusion that makes people file the next candidate by resemblance instead
# of by the rule. ../checks/catalogue-eval.nix asserts that no domain name is any entry's key, and
# ../modules/cluster.nix refuses a NAMESPACE value that collides with one either.
#
# ── THE OVERLAP IS REAL, AND SAYING SO IS THE POINT ────────────────────────────────────────────
#
# Three of the four trackers below can be described as "it tracks what I have", and a reader who
# stops there will conclude that two of them are redundant. They are not the same claim, and the
# field that separates them is `unit` -- WHAT ONE ROW IS:
#
#   `object`   one physical thing, identified individually and kept. Two of the same model are two
#              rows, because the warranty, the serial number and the receipt belong to one of them
#              and not the other.
#   `product`  a TYPE, carrying a quantity. The record knows you hold six of something; it does not
#              know which six, and there is nowhere to put a serial number because the question is
#              not asked.
#   `task`     an obligation with a recurrence rule. It has no physical referent at all -- what is
#              stored is when it is next due and who owes it.
#
# That reduces the overlap to one honest statement instead of three vague ones: the two `object`
# trackers below really are two answers to ONE question and running both means deciding which is
# authoritative, while the `product` tracker overlaps them only on the English word "inventory".
# Written up, with the evidence, in
# ../studies/four-applications-and-one-question-what-do-i-have.md.
#
# ── FIELDS ─────────────────────────────────────────────────────────────────────────────────────
#
# Shared by both groups. Every one is consumed by ../modules/cluster.nix, by a check, or by both:
#
#   `image`        container image REPOSITORY, with no tag. The tag is the declared workload's
#                  `version`: which version a household runs is a decision about that household's
#                  appetite for a schema migration, not a property of the software.
#   `ports`        named container-side ports, `<name> = <number>`. A container port is a property
#                  of the software rather than of any network, which is the one kind of number a
#                  public catalogue may carry.
#   `primaryPort`  which of those the readiness probe watches and a front would route to.
#   `state`        the container-internal paths this software writes, `<name> = <mountPath>`. What
#                  BACKS each one is a value the consumer supplies; where it lands inside the
#                  container is knowledge and lives here.
#   `env`          plain environment the software needs in order to be CORRECT. Never sizing, never
#                  credentials, never an address, and never policy -- "registrations are closed" and
#                  "the timezone is X" are decisions about one household and are not here.
#   `args`         entrypoint arguments in the same spirit.
#   `readiness`    probe shape and timing. `path` is the HTTP path that answers, or `null` for a TCP
#                  connect where the application has no cheap health endpoint. The seconds are
#                  measured rather than guessed -- see ../experiments/probe-readiness.sh.
#   `liveness`     an independent restart opinion where the software has one, or absent. Readiness
#                  only decides whether traffic reaches a process; liveness is stated separately
#                  because its verdict kills that process and therefore needs its own evidence.
#   `background`   WHAT THE APPLICATION DOES WHEN NOBODY IS LOOKING, or `null` when everything it
#                  computes is computed in answer to a request. This is the field that decides
#                  whether idling at zero replicas is lossless or merely quiet: a request-driven
#                  application at zero has nothing to miss, and one with a scheduler silently defers
#                  every reminder it would have sent. `null` is a claim, not a blank -- see
#                  ../studies/scale-to-zero-is-not-free-for-an-application-with-a-scheduler.md.
#   `identity`     WHICH IDENTITY MODEL the image implements, because these four implement three
#                  different ones and getting it wrong is a crash loop or a silently unwritable
#                  directory:
#                    "root"       the image must run as root; a non-root UID fails at startup.
#                    "puid"       the image reads a UID/GID pair from its environment, starts as
#                                 root, chowns its own data directory, then drops.
#                    "runAsUser"  the image runs as whatever UID the pod gives it and chowns
#                                 nothing; the directory must ALREADY be owned by that UID.
#                  `null` where this catalogue has not established it, which is a different
#                  statement from "it does not matter". THE NUMBERS ARE NEVER HERE: which UID a
#                  household uses is a value. And whichever model applies, `fsGroup` must not be
#                  set on node-path state -- it recursively chowns the host directory itself.
#   `requiredSecretEnv`
#                  environment variables the application cannot be CORRECT without and that carry a
#                  credential, so they can only arrive from a Secret. The NAMES are knowledge; the
#                  values are the consumer's, and nothing here can carry one. An empty list is
#                  meaningful: it says this application's credentials are established some other
#                  way, which for two entries below is genuinely true and is stated in their notes.
#   `note`         what the entry is, and every non-obvious thing about running it.
#
# Group-specific:
#
#   `domain`       (trackers) `belongings` or `housekeeping`, per the rule above.
#   `unit`         (trackers) `object`, `product` or `task`, per the overlap note above.
#   `serves`       (companions) the tracker key this companion feeds. A KEY IN THIS FILE, never a
#                  URL and never a Service name: how the companion reaches it is a fleet question
#                  with a fleet answer, and the one thing that is universal -- that it must arrive
#                  through whatever wakes the tracker -- is governed in ../modules/cluster.nix.
{ ... }:
{
  # ── Trackers: the household's own record ─────────────────────────────────────────────────────
  trackers = {
    dumbassets = {
      domain = "belongings";
      unit = "object";
      image = "dumbwareio/dumbassets";
      ports.http = 3000;
      primaryPort = "http";
      state.data = "/app/data";
      env = { };
      args = [ ];
      identity = "root";
      background = null;
      requiredSecretEnv = [ "DUMBASSETS_PIN" ];

      readiness = {
        path = "/";
        initialDelaySeconds = 0;
        periodSeconds = 5;
        timeoutSeconds = 1;
        failureThreshold = 24;
      };
      liveness = {
        path = "/";
        periodSeconds = 15;
        timeoutSeconds = 1;
        failureThreshold = 6;
      };

      note = ''
        An asset tracker: one row per thing you own, carrying its purchase, its warranty, its
        maintenance history and the files that go with it -- the receipt, the manual, the photo.
        Sub-assets hang off a parent, which is how a machine and its accessories stay one record.

        THERE IS NO DATABASE. The whole inventory is a JSON document on disk beside the uploaded
        files, which has two consequences worth knowing before it is deployed rather than after.
        It is a SINGLE WRITER in the strongest sense -- two processes with the file open lose each
        other's writes with no error and no lock to notice -- so the rendered Deployment must never
        roll, and `state` is what forces that. And the whole record is one file: a backup of that
        directory is the entire inventory, and a truncated write of it is the entire inventory too.

        THE IMAGE MUST RUN AS ROOT, and this is the entry that pays for the `identity` field. At
        startup it writes a manifest into its own application directory, which a non-root UID
        cannot -- the container gets EACCES and crash-loops before it ever serves a request. The
        data directory therefore has to be owned to match, which makes this the one entry here that
        does not fit a household's ordinary "everything runs as one unprivileged person" rule. Said
        out loud rather than left to be discovered at three in the morning.

        ITS ACCESS MODEL IS ONE SHARED PIN, not accounts. `DUMBASSETS_PIN` is the whole of it:
        there are no users, so there is no per-person attribution and no way to give somebody
        read-only access. For a household record of high-value objects that is often exactly right,
        and it is the sharpest difference between this entry and the other `object` tracker below.

        EVERYTHING IT COMPUTES IS COMPUTED ON REQUEST -- warranty expiry and service dates are
        queries over the document, not jobs -- so `background` is null and idling at zero costs
        nothing but the cold start.
      '';
    };

    homebox = {
      domain = "belongings";
      unit = "object";
      image = "ghcr.io/sysadminsmedia/homebox";
      ports.http = 7745;
      primaryPort = "http";
      state.data = "/data";
      args = [ ];
      identity = "runAsUser";
      background = null;
      requiredSecretEnv = [ "HBOX_AUTH_API_KEY_PEPPER" ];

      env = {
        # WHERE the database lands and HOW it is opened. Both are knowledge: the path is where the
        # mounted directory is, and every pragma below is a correctness setting rather than tuning.
        # `busy_timeout` is the one that matters most -- without it a second connection arriving
        # during a write gets SQLITE_BUSY immediately and the request fails, where waiting two
        # seconds would have succeeded. `journal_mode=WAL` lets a reader and the writer coexist at
        # all, and `_fk=1` turns on the foreign-key enforcement SQLite ships DISABLED by default,
        # which is the setting people are most surprised to learn they never had.
        HBOX_DATABASE_SQLITE_PATH = "/data/homebox.db?_pragma=busy_timeout=2000&_pragma=journal_mode=WAL&_fk=1&_time_format=sqlite";

        # Attachments are files under the same directory as the database rather than an object
        # store. Two settings, one decision: the connection string selects the local filesystem
        # backend, and the prefix is the subdirectory it owns.
        HBOX_STORAGE_CONN_STRING = "file:///?no_tmp_dir=true";
        HBOX_STORAGE_PREFIX_PATH = "data";

        # Not a log level and not a feature flag: the development mode serves differently and is
        # not what a household is running.
        HBOX_MODE = "production";
      };

      readiness = {
        path = "/api/v1/status";
        initialDelaySeconds = 0;
        periodSeconds = 5;
        timeoutSeconds = 1;
        failureThreshold = 24;
      };
      liveness = {
        path = "/api/v1/status";
        periodSeconds = 15;
        timeoutSeconds = 1;
        failureThreshold = 6;
      };

      note = ''
        A home inventory: one row per item, with a LOCATION, LABELS, a quantity, a purchase price,
        a warranty and attachments. The location model is what distinguishes it from a flat asset
        list -- items live in nested places, and the question it is built to answer is "where is
        it" as much as "do I own it".

        A Go binary with an embedded SQLite database and an attachment tree in the same directory,
        so there is no second container and no connection string to anything. Single writer, so
        the rendered Deployment must never roll.

        `HBOX_AUTH_API_KEY_PEPPER` IS NOT AN ORDINARY SECRET, and this is the trap. It must be at
        least 32 bytes or the application refuses to start; it must be the SAME value across every
        restart; and if it changes, every API key and every login session becomes unreadable while
        the inventory itself is untouched. So the failure it produces is "nobody can log in and the
        data looks fine", which reads as a lost password rather than as a changed configuration.
        Generate it once, keep it in a Secret, and never regenerate it as part of a redeploy.

        IT RUNS AS THE UID THE POD GIVES IT and chowns nothing, which means the directory has to be
        owned correctly BEFORE the first start -- an unwritable data directory here is not a crash
        but a startup error about the database. And `fsGroup` must not be used to fix that: on
        node-path state it recursively chowns the host directory, which is somebody's curated
        filesystem rather than a scratch volume.

        `background` IS NULL, and deliberately so as a claim about this catalogue rather than about
        the software: nothing configured here runs on a timer, so an idle instance has nothing to
        miss. An operator who turns on a notifier that mails on a schedule has changed that, and
        should say so where it is declared.
      '';
    };

    grocy = {
      domain = "housekeeping";
      unit = "product";
      image = "lscr.io/linuxserver/grocy";
      ports.http = 80;
      primaryPort = "http";
      state.config = "/config";
      env = { };
      args = [ ];
      identity = "puid";
      background = null;
      requiredSecretEnv = [ ];

      readiness = {
        # A TCP CONNECT, not an HTTP GET, and that is honesty rather than laziness: this image is
        # a web server in front of a PHP runtime, and every path it serves either redirects to a
        # login or runs application code. There is no cheap endpoint that means "ready" and nothing
        # else, so probing one would either be a lie about what was checked or a page render on
        # every probe.
        path = null;
        # NOT PADDING. The application migrates its own schema on start, and the runtime behind
        # the web server is not accepting connections until it has. Probing sooner spends the
        # failure budget on a certainty.
        initialDelaySeconds = 15;
        periodSeconds = 5;
        timeoutSeconds = 1;
        failureThreshold = 24;
      };
      liveness = {
        path = null;
        periodSeconds = 15;
        timeoutSeconds = 1;
        failureThreshold = 6;
      };

      note = ''
        The household ERP: stock, shopping list, chores, tasks, batteries, recipes and meal plan.
        Its record is a PRODUCT with a LEVEL -- how much of a thing is in the house, where it is
        kept, when the oldest of it goes off, and how little of it there may be before it belongs
        on the shopping list. It does not know WHICH tin you hold, and there is nowhere to record a
        serial number, because that is not the question it asks. That is the whole difference
        between this entry and the two `object` trackers above, and it survives every superficial
        resemblance between the word "inventory" in all three.

        A PHP application behind a web server in one image, with SQLite underneath and one
        directory holding all of it: the settings, the database, and the uploaded files. Single
        writer.

        IT MIGRATES ITS OWN SCHEMA ON START, which is why the probe is patient and why the version
        a household runs is a decision it should make deliberately. A floating tag runs a migration
        on a deploy nobody reviewed, and a migration is the one operation here that is not
        reversible by restarting the previous image.

        IDENTITY ARRIVES AS ENVIRONMENT. The image reads a UID and a GID, starts as root, chowns
        its configuration directory to them and drops -- so unlike the trackers above, the
        directory does NOT have to be correctly owned in advance, and unlike the asset tracker it
        does not stay root. The two numbers are values and are supplied where the workload is
        declared.

        IT ALSO HAS CHORES, WHICH IS THE ONE HONEST OVERLAP INSIDE ITS OWN DOMAIN. A household that
        runs both this and the chore tracker below has two places a recurring task can live, and
        nothing anywhere will reconcile them. That is a decision to make once and write down, not a
        bug -- see ../studies/four-applications-and-one-question-what-do-i-have.md.

        NO `requiredSecretEnv`: its own accounts and its API keys live in its database, which is on
        the state directory. There is no credential to inject and naming a Secret for it would
        render an environment variable nothing reads.
      '';
    };

    donetick = {
      domain = "housekeeping";
      unit = "task";
      image = "donetick/donetick";
      ports.http = 2021;
      primaryPort = "http";
      identity = "runAsUser";
      requiredSecretEnv = [ ];
      args = [ ];

      state = {
        # TWO DIRECTORIES, AND THEY ARE NOT INTERCHANGEABLE. The configuration file the application
        # reads at startup, and the database it writes forever. In the layout the image ships, the
        # second is nested inside the first -- which invites backing only the outer one and calling
        # it done. Both are named here so both must be backed.
        config = "/config";
        data = "/usr/src/app/data";
      };

      env = {
        # Where the database file is, inside the directory above.
        DT_SQLITE_PATH = "/usr/src/app/data/donetick.db";
        # WHICH CONFIGURATION FILE IT READS, resolved relative to the working directory as
        # `config/<value>.yaml` -- so this value and the mount path above are two halves of one
        # arrangement, and changing either alone means the application starts with defaults it was
        # never configured with.
        DT_ENV = "selfhosted";
      };

      background = "a reminder scheduler (due, pre-due and overdue) and a realtime channel that pushes changes to open clients";

      readiness = {
        # It serves its API and its single-page front end on ONE port, and the root path returns
        # the front end once boot is complete -- which makes it a real readiness signal rather than
        # a convenient one.
        path = "/";
        initialDelaySeconds = 0;
        periodSeconds = 5;
        timeoutSeconds = 1;
        failureThreshold = 24;
      };
      liveness = {
        path = "/";
        periodSeconds = 15;
        timeoutSeconds = 1;
        failureThreshold = 6;
      };

      note = ''
        A chore and recurring-task tracker: the record is an obligation with a recurrence rule, a
        due date and a PERSON it belongs to. That last part is why it has real accounts where the
        asset tracker has a shared PIN -- a chore nobody is assigned is a note, and the whole point
        of the application is that somebody owes it.

        A Go binary with SQLite, serving both halves on one port.

        IT IS THE ONE ENTRY HERE WITH A SCHEDULER, and that is the reason `background` exists as a
        field at all. It evaluates what is due, what is about to be, and what is late, and it holds
        a realtime channel open for clients that are watching. At zero replicas none of that runs:
        the reminders are not late, they are simply never evaluated until the next request wakes
        the pod, and the realtime channel reconnects on wake having missed the interval. That may
        be an entirely acceptable trade for a household -- it is not a fault -- but it must be a
        decision rather than a surprise, so ../modules/cluster.nix warns when this workload is
        declared scale-to-zero. Written up in
        ../studies/scale-to-zero-is-not-free-for-an-application-with-a-scheduler.md.

        ITS CREDENTIALS LIVE IN THE CONFIGURATION FILE, NOT IN ITS ENVIRONMENT, which is why
        `requiredSecretEnv` is empty and why that empty list is a statement rather than a gap. A
        notifier token, a session-signing key and an identity-provider client secret all sit in the
        file it reads from the config directory -- so THAT DIRECTORY HOLDS SECRETS and inherits
        whatever protection the household gives to secrets, which a directory called "config" does
        not obviously advertise. It is the one place in this catalogue where state and credentials
        are the same object.
      '';
    };
  };

  # ── Companions: no record of their own ───────────────────────────────────────────────────────
  #
  # A companion is not a smaller tracker and the distinction is not one of size. It is that
  # everything it does becomes a change in somebody else's database: turn it off and no record is
  # lost, only a way of writing to one. That is what makes it correct to deploy it beside the
  # tracker it serves, in the same namespace, by whoever runs that tracker -- and what makes the
  # relationship between the two something this repository has to govern rather than document.
  companions = {
    barcodebuddy = {
      serves = "grocy";
      image = "f0rc3/barcodebuddy";
      ports.http = 80;
      primaryPort = "http";
      state.config = "/config";
      env = { };
      args = [ ];
      # NOT ESTABLISHED HERE, which is a different statement from "it does not matter". The
      # identity model of this image has not been verified the way the four trackers' have, and a
      # guess in this field is worth less than an admission: a wrong one produces either a crash
      # loop or a directory the application cannot write, and both look like something else.
      identity = null;
      background = null;
      requiredSecretEnv = [ ];

      readiness = {
        path = null;
        initialDelaySeconds = 10;
        periodSeconds = 5;
        timeoutSeconds = 1;
        failureThreshold = 24;
      };

      note = ''
        A barcode companion for the household ERP: a scanner (or a phone, or a hand-typed number)
        sends it a code, it looks the product up, and it tells the ERP to add or remove stock.

        IT HOLDS NO RECORD. Every scan becomes a stock movement in the ERP's database; what stays
        here is a small amount of its own configuration and a lookup cache. That is exactly the
        `companions` test, and it is why this is not a third `housekeeping` tracker: there is
        nothing in it to be authoritative about.

        IT REACHES THE ERP OVER THE ERP'S OWN HTTP API, with a URL and an API key configured once
        inside this application's own interface and stored in its configuration directory -- so,
        like the chore tracker, its credential arrives with its state rather than through its
        environment, and `requiredSecretEnv` is empty for that reason rather than for want of a
        credential.

        AND HERE IS THE COUPLING THAT MATTERS. If the ERP is allowed to idle at zero replicas, the
        request this companion makes has to be the request that WAKES it. A wake front stands in
        front of the address the outside world uses, not in front of the in-cluster Service -- so a
        companion that dials the Service directly reaches a Deployment with no pods, gets nothing,
        and the ERP never wakes: the scan is lost and both applications look healthy. Pointing the
        companion at the same front everybody else uses fixes it completely, and lets BOTH scale to
        zero despite the dependency. ../modules/cluster.nix refuses the broken arrangement by name.
        Full reasoning in ../studies/a-companion-cannot-wake-the-tracker-it-depends-on.md.
      '';
    };
  };
}
