/-
Copyright (c) 2022 Mac Malone. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Mac Malone
-/
import Lake.Build.Targets

open System
namespace Lake

/-- Compute a topological ordering of the package's transitive dependencies. -/
def Package.recComputeDeps (self : Package) : IndexBuildM (Array Package) := do
  let mut deps := #[]
  let mut depSet := PackageSet.empty
  for dep in self.deps do
    for depDep in (← recBuild <| dep.facet `deps) do
      unless depSet.contains depDep do
        deps := deps.push depDep
        depSet := depSet.insert depDep
    unless depSet.contains dep do
      deps := deps.push dep
      depSet := depSet.insert dep
  return deps

/-- The `PackageFacetConfig` for the builtin `depsFacet`. -/
def Package.depsFacetConfig : PackageFacetConfig depsFacet :=
  mkFacetConfig (·.recComputeDeps)

/-- Build the `extraDepTarget` for the package and its transitive dependencies. -/
def Package.recBuildExtraDepTargets (self : Package) : IndexBuildM (BuildJob Unit) := do
  let mut job := BuildJob.nil
  for dep in self.deps do
    job ← job.mix (← dep.extraDep.recBuild)
  job.mix <| ← self.extraDepTarget.activate

/-- The `PackageFacetConfig` for the builtin `dynlibFacet`. -/
def Package.extraDepFacetConfig : PackageFacetConfig extraDepFacet :=
  mkFacetJobConfig (·.recBuildExtraDepTargets)

/-- Download and unpack the package's prebuilt release archive (from GitHub). -/
def Package.fetchRelease (self : Package) : SchedulerM (BuildJob Unit) := Job.async do
  let some (repoUrl, tag) := self.release? | do
    logWarning "wanted prebuilt release, but release repository and tag was not known"
    return ((), .nil)
  let archiveName := self.releaseArchive?.getD tag
  let archiveFileName := s!"{archiveName}-{osDescriptor}.tar.gz"
  let url := s!"{repoUrl}/releases/download/{tag}/{archiveFileName}"
  let localArchiveFile := self.buildDir / archiveFileName
  let logName := s!"{self.name}/{tag}/{archiveFileName}"
  let trace ← buildFileUnlessUpToDate localArchiveFile (Hash.ofString url) do
    download logName url localArchiveFile
    untar logName localArchiveFile self.buildDir
  return ((), trace)

/-- The `PackageFacetConfig` for the builtin `releaseFacet`. -/
def Package.releaseFacetConfig : PackageFacetConfig releaseFacet :=
  mkFacetJobConfig (·.fetchRelease)

open Package in
/--
A package facet name to build function map that contains builders for
the initial set of Lake package facets (e.g., `extraDep`).
-/
def initPackageFacetConfigs : DNameMap PackageFacetConfig :=
  DNameMap.empty
  |>.insert depsFacet depsFacetConfig
  |>.insert extraDepFacet extraDepFacetConfig
  |>.insert releaseFacet releaseFacetConfig
