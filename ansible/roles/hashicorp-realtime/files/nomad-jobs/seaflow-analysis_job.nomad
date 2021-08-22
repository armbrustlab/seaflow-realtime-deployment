job "seaflow-analysis_job" {
  datacenters = ["dc1"]

  type = "batch"

  periodic {
    cron = "*/15 * * * *"  // every 15 minutes
    prohibit_overlap = true
    time_zone = "UTC"
  }

  group "seaflow-analysis_group" {
    count = 1

    # No restart attempts
    reschedule {
      attempts = 0
      unlimited = false
    }

    volume "jobs_data" {
      type = "host"
      source = "jobs_data"
    }

    task "seaflow-analysis-setup-filter_task" {
      driver = "docker"

      config {
        image = "ctberthiaume/seaflowpy:local"
        command = "/local/run.sh"
        mount {
          type = "bind"
          target = "/jobs_data"
          source = "/jobs_data"
        }
      }

      // volume_mount {
      //   volume = "jobs_data"
      //   destination = "/jobs_data"
      // }

      template {
        data = <<EOH
{{ key "appconfig/seaflow-analysis/dbgz" }}
        EOH
        destination = "local/base.db.base64"
        change_mode = "noop"
        perms = "644"
      }

      template {
        data = <<EOH
#!/usr/bin/env bash
# Perform SeaFlow setup and filtering

CRUISE="{{ key "cruise/name" }}"
OUTDIR="/jobs_data/seaflow-analysis/${CRUISE}"
RAWDATADIR="/jobs_data/seaflow-transfer/${CRUISE}/evt"
SERIAL="{{ key "appconfig/seaflow-analysis/serial" }}"
DBFILE="${OUTDIR}/${CRUISE}.db"

echo "seaflowpy version = $(seaflowpy version)"
echo "user = $(id)"
echo "ls -alh /jobs_data"
ls -alh /jobs_data

# Create output directory if it doesn't exist
if [[ ! -d "${OUTDIR}" ]]; then
  echo "Creating output directory ${OUTDIR}"
  mkdir -p "${OUTDIR}" || exit $?
fi

# Create an new empty database if one doesn't exist
if [ ! -e "$DBFILE" ]; then
  echo "Creating $DBFILE with cruise=$CRUISE and inst=$SERIAL"
  seaflowpy db create -c "$CRUISE" -s "$SERIAL" -d "$DBFILE" || exit $?
fi

# Overwrite any existing filter and gating params with the base db pulled from
# consul
# First extract the base db, which is base64 encoded gzipped content
echo "Overwriting filter, gating, poly tables in ${DBTABLE} with data from consul"
# Work backward from this
# gzip -c base.db | base64 | consul kv put appconfig/seaflow-analysis/dbgz -
base64 --decode < /local/base.db.base64 | gzip -dc > /local/base.db  # location from other template stanza
sqlite3 "${DBFILE}" 'drop table filter' || exit $?
sqlite3 /local/base.db ".dump filter" | sqlite3 "${DBFILE}" || exit $?
sqlite3 "${DBFILE}" 'drop table gating' || exit $?
sqlite3 /local/base.db ".dump gating" | sqlite3 "${DBFILE}" || exit $?
sqlite3 "${DBFILE}" 'drop table poly' || exit $?
sqlite3 /local/base.db ".dump poly" | sqlite3 "${DBFILE}" || exit $?

# Find and import all SFL files in RAWDATADIR
echo "Importing SFL data in $RAWDATADIR"
echo "Saving cleaned and concatenated SFL file at ${OUTDIR}/${CRUISE}.sfl"
# Just going to assume there are no newlines in filenames here (there shouldn't be!)
seaflowpy sfl print $(/usr/bin/find "$RAWDATADIR" -name '*.sfl' | sort) > "${OUTDIR}/${CRUISE}.concatenated.sfl" || exit $?
seaflowpy db import-sfl -f "${OUTDIR}/${CRUISE}.concatenated.sfl" "$DBFILE" || exit $?

# Filter new files with seaflowpy
echo "Filtering data in ${RAWDATADIR} and writing to ${OUTDIR}"
seaflowpy filter local -p 2 --delta -e "$RAWDATADIR" -d "$DBFILE" -o "$OUTDIR/${CRUISE}_opp" || exit $?
        EOH
        destination = "/local/run.sh"
        change_mode = "restart"
        perms = "755"
      }

      resources {
        memory = 2000
        cpu = 2000
      }

      lifecycle {
        hook = "prestart"
        sidecar = false
      }
    }

    task "seaflow-analysis-classification_task" {
      driver = "docker"

      config {
        image = "ctberthiaume/popcycle:local"
        command = "/local/run.sh"
        mount {
          type = "bind"
          target = "/jobs_data"
          source = "/jobs_data"
        }
      }

      // volume_mount {
      //   volume = "jobs_data"
      //   destination = "/jobs_data"
      // }

      template {
        data = <<EOH
#!/usr/bin/env Rscript

parser <- optparse::OptionParser(usage="usage: realtime-classify.R --db FILE --vct-dir FILE --opp-dir DIR [options]")
parser <- optparse::add_option(parser, c("--db"), type="character", default="",
  help="Popcycle database file. Required.",
  metavar="FILE")
parser <- optparse::add_option(parser, c("--opp-dir"), type="character", default="",
  help="OPP directory. Required.",
  metavar="DIR")
parser <- optparse::add_option(parser, c("--vct-dir"), type="character", default="",
  help="VCT directory. Required.",
  metavar="DIR")
parser <- optparse::add_option(parser, c("--stats-file"), type="character", default="",
  help="Stats table output file.",
  metavar="FILE")
parser <- optparse::add_option(parser, c("--sfl-file"), type="character", default="",
  help="SFL table output file.",
  metavar="FILE")
parser <- optparse::add_option(parser, c("--plot-vct-file"), type="character", default="",
  help="VCT plot output file.",
  metavar="FILE")
parser <- optparse::add_option(parser, c("--plot-gates-file"), type="character", default="",
  help="Gates plot output file.",
  metavar="FILE")

p <- optparse::parse_args2(parser)
if (p$options$db == "" || p$options$opp_dir == "" || p$options$vct_dir == "") {
  # Do nothing if db, opp_dir, vct_dir are not specified
  message("error: must specify all of --db, --opp-dir, --vct-dir")
  optparse::print_help(parser)
  quit(save="no", status=10)
} else {
  db <- p$options$db
  opp_dir <- p$options$opp_dir
  vct_dir <- p$options$vct_dir

  if (!dir.exists(opp_dir) || !file.exists(db)) {
    message(paste0("opp_dir or db does not exist"))
    quit(save=FALSE, status=11)
  }
}

stats_file <- p$options$stats_file
sfl_file <- p$options$sfl_file
plot_vct_file <- p$options$plot_vct_file
plot_gates_file <- p$options$plot_gates_file

inst <- popcycle::get.inst(db)
cruise <-popcycle::get.cruise(db)

dated_msg <- function(...) {
  message(format(Sys.time(), "%Y-%m-%d %H:%M:%OS3"), ": ", ...)
}

dated_msg("Start")
message("Configuration:")
message("--------------")
message(paste0("db = ", db))
message(paste0("cruise (from db) = ", cruise))
message(paste0("serial (from db) = ", inst))
message(paste0("opp-dir = ", opp_dir))
message(paste0("vct-dir = ", vct_dir))
message(paste0("stats-file = ", stats_file))
message(paste0("sfl-file = ", sfl_file))
message(paste0("plot-vct-file = ", plot_vct_file))
message(paste0("plot-gates-file = ", plot_gates_file))
message("--------------")

############################
### ANALYZE NEW FILE(s) ###
############################
opp_list <- popcycle::get.opp.files(db, all.files=FALSE)
vct_list <- unique(popcycle::get.vct.table(db)$file)
files_to_gate <- setdiff(opp_list, vct_list)
dated_msg(paste0("gating ", length(files_to_gate), " files"))
popcycle::classify.opp.files(db, opp_dir, files_to_gate, vct_dir)

##########################
### Save Stats and SFL ###
##########################
if (stats_file != "") {
  stat <- popcycle::get.stat.table(db)
  statcols <- c(
    'time', 'lat', 'lon', 'temp', 'salinity', 'par',
    'stream_pressure', 'file_duration', 'event_rate', 'opp_evt_ratio',
    'pop', 'n_count', 'chl_med', 'pe_med', 'fsc_med',
    'diam_mid_med', 'Qc_mid_med', 'quantile', 'flag', 'flow_rate'
  )
  stat <- stat[stat$quantile == 50, statcols]
  dated_msg("saving stats file")
  write.csv(stat, stats_file, row.names=FALSE, quote=FALSE)
}
if (sfl_file != "") {
  sfl <- popcycle::get.sfl.table(db)
  dated_msg("saving SFL file")
  write.csv(sfl, sfl_file, row.names=FALSE, quote=FALSE)
}

######################
### PLOT CYTOGRAMS ###
######################
if (plot_vct_file != "" || plot_gates_file != "") {
  opp_list <- popcycle::get.opp.files(db)
  last_file <- tail(opp_list,1)
  vct <- popcycle::get.vct.by.file(db, vct_dir, last_file, col_select=c("fsc_small", "chl_small", "pop_q50", "q50"))
  vct <- vct[vct$q50, ]
  vct$file <- vct$file_id
  vct$pop <- vct$pop_q50

  if (plot_vct_file != "") {
    dated_msg("creating VCT cytogram")
    ggplot2::ggsave(
      plot_vct_file,
      popcycle::plot_vct_cytogram(vct, "fsc_small","chl_small", transform=FALSE),
      width=10, height=6, unit='in', dpi=150
    )
  }

  if (plot_gates_file != "") {
    dated_msg("creating Gate cytogram")
    ggplot2::ggsave(
      plot_gates_file,
      popcycle::plot_cytogram(vct, para.x="fsc_small", para.y="chl_small", bins=200, transform=FALSE),
      width=10, height=6, unit='in', dpi=150
    )
  }
}

dated_msg("Done")

        EOH
        destination = "/local/cron_job.R"
        change_mode = "restart"
        perms = "755"
      }

      template {
        data = <<EOH
#!/usr/bin/env bash
# Perform SeaFlow classification

CRUISE="{{ key "cruise/name" }}"
OUTDIR="/jobs_data/seaflow-analysis/${CRUISE}"
DBFILE="${OUTDIR}/${CRUISE}.db"
OPPDIR="${OUTDIR}/${CRUISE}_opp"
VCTDIR="${OUTDIR}/${CRUISE}_vct"
STATSFILE="${OUTDIR}/stat.csv"
SFLFILE="${OUTDIR}/sfl.popcycle.csv"
PLOTVCTFILE="${OUTDIR}/vct.cytogram.png"
PLOTGATESFILE="${OUTDIR}/gate.cytogram.png"

Rscript --slave -e 'message(packageVersion("popcycle"))'

# Classify and produce summary image files
echo "Classifying data in ${OUTDIR}"
Rscript --slave /local/cron_job.R \
  --db "${DBFILE}" \
  --opp-dir "${OPPDIR}" \
  --vct-dir "${VCTDIR}" \
  --stats-file "${STATSFILE}" \
  --sfl-file "${SFLFILE}" \
  --plot-vct-file "${PLOTVCTFILE}" \
  --plot-gates-file "${PLOTGATESFILE}"
        EOH
        destination = "/local/run.sh"
        change_mode = "restart"
        perms = "755"
      }

      resources {
        memory = 5000
        cpu = 2000
      }
    }
  }
}
