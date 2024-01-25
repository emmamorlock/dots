xquery version "3.1";

(:~  
: Ce module permet de créer dans la base de données "dots" les documents XML "dots_db_switcher.xml" et "dots_default_metadata_mapping.xml".
: "dots_db_switcher.xml" permet:
: - de recenser toutes les ressources disponibles
: - de préciser le type de ressource ('project' pour une collection de niveau 1, 'collection' ou 'document') 
: - d'indiquer pour chaque ressource son identifiant (@dtsResourceId)
: - et d'indiquer le nom de la db BaseX à laquelle appartient la ressource (@dbName)
: Ces informations servent au routeur DTS pour savoir pour chaque ressource dans quelle db trouver les registres DoTS qui la concerne.
: "dots_default_metadata_mapping.xml" est un document pour déclarer par défaut des métadonnées de description des documents.
: Il n'est utilisé que si aucun autre document "metadata_mapping" n'est disponible
: @author École nationale des chartes
: @since 2023-06-14
: @version  1.0
:)

module namespace dots.switcher = "https://github.com/chartes/dots/builder/switcher"; (: changer ccg par "sw"? "switcher"? :)

import module namespace functx = 'http://www.functx.com';

import module namespace G = "https://github.com/chartes/dots/globals" at "../globals.xqm";
import module namespace cc = "https://github.com/chartes/dots/builder/cc" at "resources_register_builder.xqm";
import module namespace var = "https://github.com/chartes/dots/variables" at "../project_variables.xqm";

declare default element namespace "https://github.com/chartes/dots/";
declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace dc = "http://purl.org/dc/elements/1.1/";
declare namespace dct = "http://purl.org/dc/terms/";

(:~ 
: Cette fonction permet d'ajouter ou modifier les deux documents XML à la db dots.
: @return 2 documents XML à ajouter à la db "dots"
: @param $G:dots chaîne de caractère, variable globale pour accéder à la db dots
: @param $dbName chaîne de caractère qui donne le nom de la db
: @param $topCollectionId chaîne de caractère correspondant à l'identifiant du projet (qui peut être différent du nom de la db)
: @see db_switch_builder.xqm;db.switcher:getTopCollection
: @see db_switch_builder.xqm;db.switcher:members
: @see db_switch_builder.xqm;db.switcher:getHeaders
:)
declare updating function dots.switcher:createSwitcher($dbName as xs:string, $topCollectionId as xs:string) {
  if (db:exists($G:dots))
  then 
    if (db:get($G:dots)//project[@dbName = $dbName])
    then ()
    else
      let $dots := db:get($G:dots)/dbSwitch
      let $totalProject := $dots//totalProjects
      let $modified := $dots//dct:modified
      let $member := $dots//member
      let $contentMember :=
        (
          dots.switcher:getTopCollection($dbName, $topCollectionId),
          dots.switcher:members($dbName, "")
        )
      return
        (
          replace value of node $modified with current-dateTime(),
          replace value of node $totalProject with xs:integer($totalProject) + 1,
          insert node $contentMember as last into $member
        )
  else
    let $dbSwitch :=
      <dbSwitch 
        xmlns="https://github.com/chartes/dots/" 
        xmlns:dct="http://purl.org/dc/terms/">
        {dots.switcher:getHeaders("dbSwitch")}
        <member>{
          dots.switcher:getTopCollection($dbName, $topCollectionId),
          dots.switcher:members($dbName, "")
        }</member>
      </dbSwitch>
    let $metadataMap :=
      <metadataMap 
        xmlns="https://github.com/chartes/dots/" 
        xmlns:dct="http://purl.org/dc/terms/">
        {dots.switcher:getHeaders("metadataMap")}
        <mapping>
          <dc:title xpath="//titleStmt/title[@type = 'main' or position() = 1]" scope="document"/>
          <dc:creator xpath="//titleStmt/author" scope="document"/>
          <dct:publisher xpath="//publicationStmt/publisher" scope="document"/>
        </mapping>
      </metadataMap>
    return
      let $validate := validate:rng-info($dbSwitch, $G:dbSwitchValidation)
      return
        (
          db:create($G:dots, ($dbSwitch, $metadataMap), ($G:dbSwitcher, $G:metadataMapping))
        )
};

(:~ 
: Cette fonction prépare l'en-tête des deux documents XML à créer pour la db dots
: @return élément XML <metadata></metadata> avec son contenu
: @param $option chaîne de caractère pour savoir si l'élément <totalProject/> doit être intégré au header
:)
declare function dots.switcher:getHeaders($option as xs:string) {
  <metadata>
    <dct:created>{current-dateTime()}</dct:created>
    <dct:modified>{current-dateTime()}</dct:modified>
    {if ($option = "dbSwitch") then <totalProjects>1</totalProjects> else ()}  
  </metadata>
};

(: Cette fonction permet de créer l'élément XML <project/> avec son identifiant (@dtsResourceId) et le nom de la db à laquelle il appartient (@dbName) 
: @return élément XML
: @param $dbName chaîne de caractère qui donne le nom de la db
: @param $topCollectionId chaîne de caractère qui donne l'identifiant du projet (top Collection)
:)
declare function dots.switcher:getTopCollection($dbName as xs:string, $topCollectionId as xs:string) {
  <project dtsResourceId="{$topCollectionId}" dbName="{$dbName}"/>
};

(: Cette fonction crée une séquence XML qui donne la liste de toutes les ressources disponibles pour la db $dbName
: @return séquence XML
: @param $dbName chaîne de caractère qui donne le nom de la db
: @param $path chaîne de caractère qui indique le chemin des ressources (dans la db $dbName)
: @see db_switch_builder.xqm;db.switcher:collection
: @see db_switch_builder.xqm;db.switcher:resource
:)
declare function dots.switcher:members($dbName as xs:string, $path as xs:string) {
  for $dir in db:dir($dbName, $path)
  where not(contains($dir, $G:metadata))
  return
    if ($dir/name() = "resource")
    then dots.switcher:resource($dbName, $dir, $path)
    else
      if ($dir != "")
      then
        (
          dots.switcher:collection($dbName, $dir, $path), 
          dots.switcher:members($dbName, concat($path, "/", $dir))
        ) 
      else ()
};

(: Cette fonction permet, pour chaque document, de créer un élément XML <document/> avec son identifiant (@dtsResourceId) et le nom de la db à laquelle il appartient (@dbName)  
: @return élément XML 
: @param $dbName chaîne de caractère qui donne le nom de la db
: @param $fileNameDocument chaîne de caractère qui donne le nom du document
: @param $pathToDocument chaîne de caractère qui donne le chemin d'accès au document (dans la db $dbName)
:)
declare function dots.switcher:resource($dbName as xs:string, $fileNameDocument as xs:string, $pathToDocument as xs:string) {
  let $doc := db:get($dbName, concat($pathToDocument, "/", $fileNameDocument))/tei:TEI
  let $id := if ($doc/@xml:id) then normalize-space($doc/@xml:id) else functx:substring-after-last(db:path($doc), "/")
  return
    if ($doc)
    then
      <document dtsResourceId="{$id}" dbName="{$dbName}"/>
    else ()
};

(: Cette fonction permet, pour chaque collection, de créer un élément XML <collection/> avec son identifiant (@dtsResourceId) et le nom de la db à laquelle il appartient (@dbName)  
: @return élément XML 
: @param $dbName chaîne de caractère qui donne le nom de la db
: @param $dirNameCollection chaîne de caractère qui donne le nom de la collection (qui sert d'identifiant)
: @param $pathToCollection chaîne de caractère qui donne le chemin d'accès à la collection (dans la db $dbName)
:)
declare function dots.switcher:collection($dbName as xs:string, $dirNameCollection as xs:string, $pathToCollection as xs:string) {
  let $totalItems := count(db:dir($dbName, $dirNameCollection))
  let $parent := if ($pathToCollection = "") then $dbName else $pathToCollection
  return
    if ($dirNameCollection = "dots") then () else <collection dtsResourceId="{$dirNameCollection}" dbName="{$dbName}"/>
};







