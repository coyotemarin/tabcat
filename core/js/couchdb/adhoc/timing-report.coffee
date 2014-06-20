###
Copyright (c) 2014, Regents of the University of California
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

  1. Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.
  2. Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in the
  documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
###
_ = require('js/vendor/underscore')._
csv = require('js/vendor/ucsv')
patient = require('../patient')
report = require('./report')
gauss = require('js/vendor/gauss/gauss')

HEADERS = [
  'patientCode',
  'encounterNum',
].concat(report.DATA_QUALITY_HEADERS).concat([
  'taskName',
  report.DATE_HEADER,
  report.VERSION_HEADER,
  'taskFinished',
  'numEvents',
  'between25',
  'betweenMedian',
  'between75',
  'rhythm25',
  'rhythmMedian',
  'rhythm75',
  'firstEvent',
  'timesBetween',
])


EVENT_TYPES = [
  'click',
  'mousedown',
  'touchstart',
]


# score how close to 1 the ratio between a and b is
scoreRhythm = (a, b) ->
  Math.pow(Math.log(a) - Math.log(b), 2)


patientHandler = (patientRecord) ->
  for encounter in patientRecord.encounters
    for task in encounter.tasks
      # times for touchstart events
      times = (
        item.now / 1000 for item in (task.eventLog ? []) \
        when item.now? and item?.event?.type in EVENT_TYPES)
      # ignore duplicate events
      times = _.uniq(times, true)

      # times between touchstart events
      timesBetween = gauss.Vector(
        times[j] - times[j - 1] for j in [1...times.length])

      # ratio of time between to previous time between
      rhythmScores = gauss.Vector(
        scoreRhythm(timesBetween[j], timesBetween[j - 1]) \
        for j in [1...timesBetween.length])

      data = [
        patientRecord.patientCode
        encounter.encounterNum + 1
      ].concat(report.getDataQualityCols(encounter)).concat([
        task.name,
        report.getDate(task),
        report.getVersion(task),
        Number(task.finishedAt?),
        times.length
        timesBetween.percentile(0.25),
        timesBetween.median()
        timesBetween.percentile(0.75),
        rhythmScores.percentile(0.25),
        rhythmScores.median(),
        rhythmScores.percentile(0.75),
      ])

      # add raw timing data, starting with time from start of task
      if times.length
        data.push(times[0] - (task.startedAt ? 0) / 1000)
        data = data.concat(timesBetween)

      report.sendCsvRow(data)


exports.list = (head, req) ->
  report.requirePatientView(req)
  start(headers: report.csvHeaders('timing-report'))

  send(csv.arrayToCsv([HEADERS]))

  patient.iterate(getRow, patientHandler)
