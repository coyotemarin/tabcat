###
Copyright (c) 2013, Regents of the University of California
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
# logic for opening encounters with patients.
@TabCAT ?= {}
TabCAT.Encounter = {}

# DB where we store patient and encounter docs
DATA_DB = 'tabcat-data'

# so we don't have to type window.localStorage in functions
localStorage = @localStorage


# Get a copy of the CouchDB doc for this encounter
TabCAT.Encounter.get = ->
  if localStorage.encounter?
    try JSON.parse(localStorage.encounter)


# get the patient code
TabCAT.Encounter.getPatientCode = ->
  TabCAT.Encounter.get()?.patientCode


# get the (random) ID of this encounter.
TabCAT.Encounter.getId = ->
  TabCAT.Encounter.get()?._id


# is there an open encounter?
TabCAT.Encounter.isOpen = ->
  TabCAT.Encounter.get()?


# get the encounter number. This should only be used in the UI, not
# stored in the database. null if unknown.
TabCAT.Encounter.getNum = ->
  encounterNum = undefined
  try
    encounterNum = parseInt(localStorage.encounterNum)

  if not encounterNum? or _.isNaN(encounterNum)
    return null
  else
    return encounterNum


# get a map from task name to a list containing scoring for each time
# that task was completed during this encounter
TabCAT.Encounter.getTaskScoring = ->
  (try JSON.parse(localStorage.encounterTaskScoring)) ? {}


# add scoring for a task to localStorage.encounterTaskScoring
#
# TabCAT.Task.finish() will call this; you don't need to call it directly
TabCAT.Encounter.addTaskScoring = (taskName, scoring) ->
  taskScoring = TabCAT.Encounter.getTaskScoring()
  taskScoring[taskName] ?= []
  taskScoring[taskName].push(scoring)

  localStorage.encounterTaskScoring = JSON.stringify(taskScoring)


# return a new encounter doc (don't upload it)
#
# Call TabCAT.Clock.reset() before this so that time fields are properly set.
TabCAT.Encounter.newDoc = (patientCode, configDoc) ->
  clockOffset = TabCAT.Clock.offset()
  date = new Date(clockOffset)

  doc =
    _id: TabCAT.Couch.randomUUID()
    type: 'encounter'
    patientCode: patientCode
    version: TabCAT.version
    year: date.getFullYear()

  user = TabCAT.User.get()
  if user?
    doc.user = user

  if configDoc?.limitedPHI
    doc.limitedPHI =
      # in JavaScript, January is 0, February is 1, etc.
      month: date.getMonth() + 1
      day: date.getDate()
      clockOffset: clockOffset

  return doc


# get the date an encounter occurred, as an ISO 8601 date (YYYY-MM-DD)
# this is long only because
TabCAT.Encounter.getISODate = (encounterDoc) ->
  console.log(JSON.stringify(encounterDoc))

  year = encounterDoc.year
  month = encounterDoc.limitedPHI?.month
  day = encounterDoc.limitedPHI?.day
  clockOffset = encounterDoc.limitedPHI?.clockOffset

  if clockOffset?
    if month? and day?
      # JS months start at 0. Check for off-by-one errors on month (#45)
      startOfDay = Date(year, month - 1, day).getTime()
      if Math.abs(clockOffset - startOfDay) > 2 * 24 * 60 * 60 * 1000
        month += 1
    else
      # this can happen if we're reading out of the patient view,
      # which includes clockOffset and year but not month/day

      # TODO: this shows the date in the current time zone, which
      # may lead to confusing results if the test happened in a very
      # different time zone. Could be fixed by
      date = new Date(clockOffset)
      month = date.getMonth() + 1
      day = date.getDate()

  if not year?
    return ''

  yearStr = year.toString()

  if not (month? and day?)
    return yearStr

  # quick and dirty zero-padding
  monthStr = (100 + month).toString()[1..]
  dayStr = (100 + day).toString()[1..]

  return "#{yearStr}-#{monthStr}-#{dayStr}"


# Promise: start an encounter and update patient doc and localStorage
# appropriately. Patient code will always be converted to all uppercase.
#
# Sample usage:
#
# TabCAT.Encounter.create(patientCode: "AAAAA").then(
#   (-> ... # proceed),
#   (xhr) -> ... # show error message on failure
# )
#
# You can set a timeout in milliseconds with options.timeout
TabCAT.Encounter.create = (options) ->
  now = $.now()
  TabCAT.Encounter.clear()
  TabCAT.Clock.reset()

  patientDoc = TabCAT.Patient.newDoc(options?.patientCode)

  $.when(TabCAT.Config.get(timeout: options?.timeout)).then(
    (config) ->
      encounterDoc = TabCAT.Encounter.newDoc(patientDoc.patientCode, config)

      patientDoc.encounterIds = [encounterDoc._id]

      # if there's already a doc for the patient, our new encounter ID will
      # be appended to the existing patient.encounterIds
      TabCAT.DB.putDoc(
        DATA_DB, patientDoc,
        expectConflict: true, now: now, timeout: options?.timeout).then(->

        TabCAT.DB.putDoc(
          DATA_DB, encounterDoc, now: now, timeout: options?.timeout).then(->

          # update localStorage
          localStorage.encounter = JSON.stringify(encounterDoc)
          # only show encounter number if we're online
          if encounterDoc._rev
            localStorage.encounterNum = patientDoc.encounterIds.length
          else
            localStorage.removeItem('encounterNum')
          return
        )
      )
  )


# Promise (can't fail): finish the current patient encounter. this clears
# local storage even if there is a problem updating the encounter doc. If
# there is no current encounter, does nothing.
#
# options:
# - administrationNotes: notes used to determine the quality of the data
#   collected in the encounter. These fields are recommended:
#   - goodForResearch (boolean): is this data useful for research?
#   - qualityIssues (sorted list of strings): specific patient issues
#     affecting data quality:
#     - behavior: behavioral disturbances
#     - education: minimal education
#     - effort: lack of effort
#     - hearing: hearing impairment
#     - motor: motor difficulties
#     - secondLanguage: e.g. ESL, different from "speech"
#     - speech: speech difficulties
#     - unreliable: unreliable informant
#     - visual: visual impairment
#     - other: (should explain in "comments")
#   - comments (text): free-form comments on the encounter
#
# goodForResearch should be required by the UI, but neither administrationNotes
# nor goodForResearch are required by this method.
TabCAT.Encounter.close = (options) ->
  now = TabCAT.Clock.now()
  encounterDoc = TabCAT.Encounter.get()
  TabCAT.Encounter.clear()

  if encounterDoc?
    encounterDoc.finishedAt = now
    if options?.administrationNotes?
      encounterDoc.administrationNotes = options.administrationNotes
    TabCAT.DB.putDoc(DATA_DB, encounterDoc)
  else
    $.Deferred().resolve()


# clear local storage relating to the current encounter
TabCAT.Encounter.clear = ->
  # remove everything starting with "encounter". This handles obsolete keys.
  for key in _.keys(localStorage)
    if key[...9] is 'encounter'
      localStorage.removeItem(key)

  TabCAT.Clock.clear()


# Promise: fetch info about an encounter.
#
# Returns:
# - _id: doc ID for encounter (same as encounterId), if encounter exsists
# - limitedPHI.clockOffset: real start time of encounter
# - patientCode: patient in encounter
# - tasks: list of task info, sorted by start time, with these fields:
#   - _id: doc ID for task
#   - name: name of task's design doc (e.g. "line-orientation")
#   - startedAt: timestamp for start of task (using encounter clock)
#   - finishedAt: timestamp for end of task, if task was finished
# - type: always "encounter"
# - year: year encounter started
#
# By default (no args), we return info about the current encounter.
#
# You may provide patientCode if you know it; otherwise we'll look it up.
TabCAT.Encounter.getInfo = (encounterId, patientCode) ->
  if not encounterId?
    encounterId = TabCAT.Encounter.getId()
    patientCode = TabCAT.Encounter.getPatientCode()

    if not (encounterId? and patientCode?)
      return $.Deferred().resolve(null)

  if patientCode?
    patientCodePromise = $.Deferred().resolve(patientCode)
  else
    patientCodePromise = TabCAT.Couch.getDoc(DATA_DB, encounterId).then(
      (encounterDoc) -> encounterDoc.patientCode)

  patientCodePromise.then((patientCode) ->

    TabCAT.Couch.getDoc(DATA_DB, '_design/core/_view/patient', query:
      startkey: [patientCode, encounterId]
      endkey: [patientCode, encounterId, []]).then((results) ->

      info = {_id: encounterId, patientCode: patientCode, tasks: []}

      # arrange encounter, patients, and tasks into a single doc
      # TODO: this code is similar to lib/app/dumpList(); merge common code?
      for {key: [__, ___, taskId, startedAt], value: doc} in results.rows
        switch doc.type
          when 'encounter'
            $.extend(info, doc)
          when 'encounterNum'
            info.encounterNum = doc.encounterNum
          when 'task'
            doc.startedAt = startedAt
            info.tasks.push(_.extend({_id: taskId}, _.omit(doc, 'type')))

      info.tasks = _.sortBy(info.tasks, (task) -> task.startedAt)

      return info
    )
  )
