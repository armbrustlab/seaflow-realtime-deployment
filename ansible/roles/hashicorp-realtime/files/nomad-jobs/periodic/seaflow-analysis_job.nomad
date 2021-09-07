variable "realtime_user" {
  type = string
  default = "ubuntu"
}

job "seaflow-analysis_job" {
  datacenters = ["dc1"]

  type = "batch"

  periodic {
    cron = "*/15 * * * *"  // every 15 minutes
    prohibit_overlap = true
    time_zone = "UTC"
  }

  parameterized {
    meta_required = ["instrument"]
  }

  # No restart attempts
  reschedule {
    attempts = 1
    unlimited = false
  }

  group "seaflow-analysis_group" {
    count = 1

    volume "jobs_data" {
      type = "host"
      source = "jobs_data"
    }

    task "setup" {
      driver = "exec"

      user = var.realtime_user

      config {
        command = "/local/run.sh"
      }

      lifecycle {
        hook = "prestart"
        sidecar = false
      }

      resources {
        memory = 300
        cpu = 300
      }

      template {
        data = <<EOH
#!/usr/bin/env bash

# Get cruise name
echo "cruise=$(consul kv get cruise/name)" > ${NOMAD_ALLOC_DIR}/data/vars
# Get instrument name
echo "instrument=${NOMAD_META_instrument}" >> ${NOMAD_ALLOC_DIR}/data/vars
# Get instrument serial
echo "serial=$(consul kv get seaflowconfig/${NOMAD_META_instrument}/serial)" >> ${NOMAD_ALLOC_DIR}/data/vars

# First extract the base db, which is base64 encoded gzipped content
# Work backward from this
# gzip -c base.db | base64 | consul kv put "seaflow-analysis/${instrument}/dbgz" -
consul kv get "seaflow-analysis/${NOMAD_META_instrument}/dbgz" | \
  base64 --decode | \
  gzip -dc > ${NOMAD_ALLOC_DIR}/data/base.db
        EOH
        destination = "/local/run.sh"
        change_mode = "restart"
        perms = "755"
      }
    }

    task "filter" {
      driver = "docker"

      volume_mount {
        volume = "jobs_data"
        destination = "/jobs_data"
      }

      config {
        image = "ctberthiaume/seaflowpy:local"
        command = "/local/run.sh"
      }

      resources {
        memory = 5000
        cpu = 300
      }

      template {
        data = <<EOH
#!/usr/bin/env bash
# Perform SeaFlow setup and filtering

set -e

# Get variables defined by setup task
source ${NOMAD_ALLOC_DIR}/data/vars

echo "seaflowpy version = $(seaflowpy version)"

outdir="/jobs_data/seaflow-analysis/${cruise}/${instrument}"
rawdatadir="/jobs_data/seaflow-transfer/${cruise}/${instrument}/evt"
dbfile="${outdir}/${cruise}.db"

echo "cruise=${cruise}"
echo "instrument=${instrument}"
echo "outdir=${outdir}"
echo "rawdatadir=${rawdatadir}"
echo "serial=${serial}"
echo "dbfile=${dbfile}"

# Create output directory if it doesn't exist
if [[ ! -d "${outdir}" ]]; then
  echo "Creating output directory ${outdir}"
  mkdir -p "${outdir}" || exit $?
fi

# Create an new empty database if one doesn't exist
if [ ! -e "$dbfile" ]; then
  echo "Creating $dbfile with cruise=$cruise and inst=$serial"
  seaflowpy db create -c "$cruise" -s "$serial" -d "$dbfile" || exit $?
fi

# Overwrite any existing filter and gating params with the base db pulled from
# consul
echo "Overwriting filter, gating, poly tables in ${dbfile} with data from consul"
sqlite3 "${dbfile}" 'drop table filter' || exit $?
sqlite3 ${NOMAD_ALLOC_DIR}/data/base.db ".dump filter" | sqlite3 "${dbfile}" || exit $?
sqlite3 "${dbfile}" 'drop table gating' || exit $?
sqlite3 ${NOMAD_ALLOC_DIR}/data/base.db ".dump gating" | sqlite3 "${dbfile}" || exit $?
sqlite3 "${dbfile}" 'drop table poly' || exit $?
sqlite3 ${NOMAD_ALLOC_DIR}/data/base.db ".dump poly" | sqlite3 "${dbfile}" || exit $?

# Find and import all SFL files in rawdatadir
echo "Importing SFL data in $rawdatadir"
echo "Saving cleaned and concatenated SFL file at ${outdir}/${cruise}.sfl"
# Just going to assume there are no newlines in filenames here (there shouldn't be!)
seaflowpy sfl print $(/usr/bin/find "$rawdatadir" -name '*.sfl' | sort) > "${outdir}/${cruise}.concatenated.sfl" || exit $?
seaflowpy db import-sfl -f "${outdir}/${cruise}.concatenated.sfl" "$dbfile" || exit $?

# Filter new files with seaflowpy
echo "Filtering data in ${rawdatadir} and writing to ${outdir}"
seaflowpy filter local -p 2 --delta -e "$rawdatadir" -d "$dbfile" -o "$outdir/${cruise}_opp" || exit $?
        EOH
        destination = "/local/run.sh"
        change_mode = "restart"
        perms = "755"
      }
    }

    task "classification" {
      driver = "docker"

      config {
        image = "ctberthiaume/popcycle:local"
        command = "/local/run.sh"
      }

      lifecycle {
        hook = "poststop"
        sidecar = false
      }

      volume_mount {
        volume = "jobs_data"
        destination = "/jobs_data"
      }

      resources {
        memory = 5000
        cpu = 300
      }

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
if (length(files_to_gate) > 0) {
  popcycle::classify.opp.files(db, opp_dir, files_to_gate, vct_dir)
}

##########################
### Save Stats and SFL ###
##########################
if (stats_file != "") {
  stat <- popcycle::create_realtime_bio(db, 50)
  dated_msg("saving stats / bio file")
  readr::write_csv(stat, stats_file)
}
if (sfl_file != "") {
  sfl <- popcycle::create_realtime_meta(db, 50)
  dated_msg("saving SFL / metadata file")
  readr::write_csv(sfl, sfl_file)
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
  vct$fsc_small <- log10(vct$fsc_small)
  vct$chl_small <- log10(vct$chl_small)

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

set -e

# Get variables defined by setup task
source ${NOMAD_ALLOC_DIR}/data/vars

outdir="/jobs_data/seaflow-analysis/${cruise}/${instrument}"
dbfile="${outdir}/${cruise}.db"
oppdir="${outdir}/${cruise}_opp"
vctdir="${outdir}/${cruise}_vct"
statsfile="${outdir}/stat.csv"
sflfile="${outdir}/sfl.popcycle.csv"
plotvctfile="${outdir}/vct.cytogram.png"
plotgatesfile="${outdir}/gate.cytogram.png"

Rscript --slave -e 'message(packageVersion("popcycle"))'

# Classify and produce summary image files
echo "Classifying data in ${outdir}"
Rscript --slave /local/cron_job.R \
  --db "${dbfile}" \
  --opp-dir "${oppdir}" \
  --vct-dir "${vctdir}" \
  --stats-file "${statsfile}" \
  --sfl-file "${sflfile}" \
  --plot-vct-file "${plotvctfile}" \
  --plot-gates-file "${plotgatesfile}"
        EOH
        destination = "/local/run.sh"
        change_mode = "restart"
        perms = "755"
      }
    }
  }
}
