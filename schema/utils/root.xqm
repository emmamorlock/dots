xquery version "3.1";

(:~  
: Ce module permet de créer un fichier de configuration général. Ce document sert ensuite pour le routeur DoTS. Spécifiquement, le rôle de ce module est de créer le document de configuration général, en intégrant toutes les collections existantes et leurs membres avec le lien vers le projet correspondant.
: @author École nationale des chartes - Philippe Pons
: @since 2023-06-14
: @version  1.0
:)

module namespace ccg = "https://github.com/chartes/dots/schema/utils/ccg";

import module namespace G = "https://github.com/chartes/dots/globals" at "../../globals.xqm";
import module namespace cc = "https://github.com/chartes/dots/schema/utils/cc" at "project.xqm";

declare default element namespace "https://github.com/chartes/dots/";
declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace dc = "http://purl.org/dc/elements/1.1/";
declare namespace dct = "http://purl.org/dc/terms/";

declare updating function ccg:create_config($idProject as xs:string, $dbName as xs:string) {
  if (db:exists($G:dots))
  then 
    let $dots := db:get($G:dots)
    let $lastUpdate := $dots/dbSwitch//dct:modified
    let $totalProjects := xs:integer($dots//totalProjects)
    let $members := ccg:members($dbName, "")
    return
      (
        replace value of node $lastUpdate with current-dateTime(),
        if ($dots//project/@dtsResourceId = $idProject)
        then ()
        else
          let $projects := $dots/dbSwitch/member
          return
          (
            replace value of node $projects with $totalProjects,
            insert node ccg:getProject($idProject, $dbName) into $projects
          ),
        for $member in $members
        let $id := $member/@dtsResourceId
        return
          if ($dots//member/node()[@dtsResourceId = $id])
          then replace node $dots//member/node()[@dtsResourceId = $id] with $member
          else 
            insert node $member as last into $dots//member,
        if (db:get($G:dots, $G:metadataMapping))
        then ()
        else
          db:put($G:dots, "/webapp/dots/schema/dots_default_metadata_mapping.xml", $G:metadataMapping)
      )
  else
    let $dbSwitch :=
      <dbSwitch 
        xmlns="https://github.com/chartes/dots/" 
        xmlns:dct="http://purl.org/dc/terms/">
        {ccg:getMetadata("dbSwitch")},
        <member>{
            ccg:getProject($idProject, $dbName),
            ccg:members($dbName, "")
        }</member>
      </dbSwitch>
    let $metadataMap :=
      <metadataMap 
        xmlns="https://github.com/chartes/dots/" 
        xmlns:dct="http://purl.org/dc/terms/">
        {ccg:getMetadata("metadataMap")}
        <mapping>
          <dc:title xpath="//titleStmt/title[@type = 'main' or position() = 1]" scope="document"/>
          <dc:creator xpath="//titleStmt/author" scope="document"/>
          <dct:publisher xpath="//publicationStmt/publisher" scope="document"/>
        </mapping>
      </metadataMap>
    return
      (
        db:create($G:dots, ($dbSwitch, $metadataMap), ($G:dbSwitcher, $G:metadataMapping))
      )
};

(:~ 
: Cette fonction se contente de construire l'en-tête <configMetadata/> du fichier de configuration
:)
declare function ccg:getMetadata($option as xs:string) {
  <metadata>
    <dct:created>{current-dateTime()}</dct:created>
    <dct:modified>{current-dateTime()}</dct:modified>
    {if ($option = "dbSwitch") then <totalProjects>1</totalProjects> else ()}  
  </metadata>
};

declare function ccg:getProject($idProject as xs:string, $dbName as xs:string) {
  <project dtsResourceId="{$idProject}" dbName="{$dbName}"/>
};

declare function ccg:members($idBdd as xs:string, $path as xs:string) {
  for $dir in db:dir($idBdd, $path)
  where not(contains($dir, $G:metadata))
  order by $dir
  return
    if (contains($dir, ".xml") or contains($dir, ".tsv"))
    then ccg:resource($idBdd, $dir, $path)
    else
      (
        ccg:collection($idBdd, $dir, $path), 
        ccg:members($idBdd, $dir)
      )
};

declare function ccg:resource($idBdd as xs:string, $resource as xs:string, $path as xs:string) {
  let $doc := db:get($idBdd, concat($path, "/", $resource))/tei:TEI
  let $id := if ($doc/@xml:id) then normalize-space($doc/@xml:id) else db:node-id($doc)
  return
    if ($doc)
    then
      <document dtsResourceId="{$id}" dbName="{$idBdd}"/>
    else ()
};

declare function ccg:collection($idBdd as xs:string, $collection as xs:string, $path as xs:string) {
  let $totalItems := count(db:dir($idBdd, $collection))
  let $parent := if ($path = "") then $idBdd else $path
  return
    if ($collection = "dots") then () else <collection dtsResourceId="{$collection}" dbName="{$idBdd}"/>
};







