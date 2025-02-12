# @summary Collect update history from the results JSON file on the targets
#
# When executing the `patching::update` task, the data that is returned to Bolt
# is also written into a "results" file. This plan reads the last JSON document
# from that results file, then formats the results in various ways.
#
# This is useful for gather patching report data on a fleet of servers.
#
# If you're using this in a larger workflow and you've run `patching::update` inline.
# You can pass the ResultSet from that task into the `history` parameter of this
# plan and we will skip retrieving the history from the targets and simply use
# that data.
#
# @param [TargetSpec] nodes
#   Set of targets to run against.
#
# @param [Optional[ResultSet]] history
#   Optional ResultSet from the `patching::update` or `patching::update_history` tasks
#   that contains update result data to be formatted.
#
# @param [Optional[String]] report_file
#   Optional filename to save the formatted repot into.
#   If `undef` is passed, then no report file will be written.
#
# @param [Enum['none', 'pretty', 'csv']] format
#   The method of formatting to use for the data.
#
# @return [String] Data string formatting in the method requested
#
plan patching::update_history (
  TargetSpec          $nodes,
  Optional[ResultSet] $history     = undef,
  Optional[String]    $report_file = 'patching_report.csv',
  # TODO JSON outputs
  Enum['none', 'pretty', 'csv'] $format = 'pretty',
) {
  $targets = run_plan('patching::get_targets', nodes => $nodes)

  ## Collect update history
  if $history {
    $_history = $history
  }
  else {
    $_history = run_task('patching::update_history', $targets)
  }

  ## Format the report
  case $format {
    'none': {
      return($_history)
    }
    'pretty': {
      $row_format = '%-30s | %-8s | %-8s'
      $header = sprintf($row_format, 'host', 'upgraded', 'installed')
      $divider = '-----------------------------------------------------'
      $output = $_history.map|$hist| {
        $num_upgraded = $hist['upgraded'].size
        $num_installed = $hist['installed'].size
        $row_format = '%-30s | %-8s | %-8s'
        $message = sprintf($row_format, $hist.target.name, $num_upgraded, $num_installed)
        $message
      }

      ## Build report
      $report = join([$header, $divider] + $output + [''], "\n")
    }
    'csv': {
      $csv_header = "host,action,name,version,kb (windows only)\n"
      $report = $_history.reduce($csv_header) |$res_memo, $res| {
        $hostname = $res.target.host
        $num_updates = $res['upgraded'].length
        $host_updates = $res['upgraded'].reduce('') |$up_memo, $up| {
          $name = $up['name']
          $version = ('version' in $up) ? {
            true    => $up['version'],
            default => '',
          }
          # if this is windows we want to print KB articles (one per line?)
          if 'kb_ids' in $up {
            # TODO: provider? - need a custom tab for windows vs linux

            # create a new line for each KB article
            $csv_line = $up['kb_ids'].reduce('') |$kb_memo, $kb| {
              $kb_line = "${hostname},upgraded,\"${name}\",\"${version}\",\"${kb}\""
              "${kb_memo}${kb_line}\n"
            }
          }
          else {
            # TODO version old? - need a custom tab for windows vs linux

            # create one line per update/upgrade
            $csv_line = "${hostname},upgraded,\"${name}\",\"${version}\",\n"
          }
          "${up_memo}${csv_line}"
        }
        "${res_memo}${host_updates}"
      }
    }
    default: {
      fail_plan("unknown format: ${format}")
    }
  }

  out::message($report)

  ## Write report to file
  if $report_file {
    file::write($report_file, $report)
  }
  return($report)
}
