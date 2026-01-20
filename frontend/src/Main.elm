port module Main exposing (main)

import Browser
import Browser.Dom as Dom
import Dict exposing (Dict)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as D
import Json.Encode as E
import Task


port saveNotes : E.Value -> Cmd msg


type alias NoteId =
    String


type alias Note =
    { id : NoteId
    , content : String
    }


type alias Model =
    { notes : Dict NoteId Note
    , activeNoteId : Maybe NoteId
    , nextId : Int
    , isEditing : Bool
    }


type Msg
    = SelectNote NoteId
    | UpdateContent String
    | NewNote
    | DeleteNote NoteId
    | ToggleEdit
    | NoOp


init : E.Value -> ( Model, Cmd Msg )
init flags =
    let
        decoded =
            D.decodeValue notesDecoder flags
                |> Result.withDefault { notes = Dict.empty, nextId = 1 }

        ( notes, activeId, nextId ) =
            if Dict.isEmpty decoded.notes then
                let
                    firstNote =
                        { id = "1", content = "" }
                in
                ( Dict.singleton "1" firstNote, Just "1", 2 )

            else
                ( decoded.notes
                , Dict.keys decoded.notes |> List.head
                , calculateNextId decoded.notes decoded.nextId
                )
    in
    ( { notes = notes
      , activeNoteId = activeId
      , nextId = nextId
      , isEditing = False
      }
    , Cmd.none
    )


calculateNextId : Dict NoteId Note -> Int -> Int
calculateNextId notes serverNextId =
    let
        maxId =
            notes
                |> Dict.keys
                |> List.filterMap String.toInt
                |> List.maximum
                |> Maybe.withDefault 0
    in
    Basics.max serverNextId (maxId + 1)


notesDecoder : D.Decoder { notes : Dict NoteId Note, nextId : Int }
notesDecoder =
    D.map2 (\n i -> { notes = n, nextId = i })
        (D.field "notes" (D.dict noteDecoder))
        (D.field "nextId" D.int)


noteDecoder : D.Decoder Note
noteDecoder =
    D.map2 Note
        (D.field "id" D.string)
        (D.field "content" D.string)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SelectNote noteId ->
            ( { model | activeNoteId = Just noteId, isEditing = False }, Cmd.none )

        UpdateContent newContent ->
            case model.activeNoteId of
                Just noteId ->
                    let
                        newNotes =
                            Dict.update noteId
                                (Maybe.map (\n -> { n | content = newContent }))
                                model.notes

                        newModel =
                            { model | notes = newNotes }
                    in
                    ( newModel, saveNotes (encodeNotes newModel) )

                Nothing ->
                    ( model, Cmd.none )

        NewNote ->
            let
                newId =
                    String.fromInt model.nextId

                newNote =
                    { id = newId, content = "" }

                newModel =
                    { model
                        | notes = Dict.insert newId newNote model.notes
                        , activeNoteId = Just newId
                        , nextId = model.nextId + 1
                        , isEditing = True
                    }
            in
            ( newModel
            , Cmd.batch
                [ saveNotes (encodeNotes newModel)
                , Task.attempt (\_ -> NoOp) (Dom.focus "editor")
                ]
            )

        DeleteNote noteId ->
            let
                newNotes =
                    Dict.remove noteId model.notes

                newActiveId =
                    if model.activeNoteId == Just noteId then
                        Dict.keys newNotes |> List.head

                    else
                        model.activeNoteId

                newModel =
                    { model | notes = newNotes, activeNoteId = newActiveId }
            in
            ( newModel, saveNotes (encodeNotes newModel) )

        ToggleEdit ->
            let
                cmd =
                    if not model.isEditing then
                        Task.attempt (\_ -> NoOp) (Dom.focus "editor")
                    else
                        Cmd.none
            in
            ( { model | isEditing = not model.isEditing }, cmd )

        NoOp ->
            ( model, Cmd.none )


encodeNotes : Model -> E.Value
encodeNotes model =
    E.object
        [ ( "notes"
          , E.dict identity encodeNote model.notes
          )
        , ( "nextId", E.int model.nextId )
        ]


encodeNote : Note -> E.Value
encodeNote note =
    E.object
        [ ( "id", E.string note.id )
        , ( "content", E.string note.content )
        ]


noteTitle : Note -> String
noteTitle note =
    let
        firstLine =
            note.content
                |> String.lines
                |> List.head
                |> Maybe.withDefault ""
                |> String.trim
    in
    if String.isEmpty firstLine then
        "Untitled"

    else if String.length firstLine > 30 then
        String.left 30 firstLine ++ "…"

    else
        firstLine


view : Model -> Html Msg
view model =
    let
        activeNote =
            model.activeNoteId
                |> Maybe.andThen (\id -> Dict.get id model.notes)

        notesList =
            model.notes
                |> Dict.values
                |> List.sortBy .id
                |> List.reverse
    in
    div [ class "app" ]
        [ aside [ class "sidebar" ]
            [ div [ class "sidebar-header" ]
                [ button [ class "new-note-btn", onClick NewNote ] [ text "+ New" ]
                ]
            , ul [ class "notes-list" ]
                (List.map (viewNoteItem model.activeNoteId) notesList)
            ]
        , main_ [ class "editor-container" ]
            [ case activeNote of
                Just note ->
                    div [ class "editor-wrapper" ]
                        [ if model.isEditing then
                            div [ class "edit-mode" ]
                                [ textarea
                                    [ id "editor"
                                    , class "editor"
                                    , value note.content
                                    , onInput UpdateContent
                                    , placeholder "Start writing..."
                                    , autofocus True
                                    ]
                                    []
                                , button [ class "done-btn", onClick ToggleEdit ] [ text "Done" ]
                                ]
                          else
                            div [ class "view-mode", onClick ToggleEdit ]
                                (renderContent note.content)
                        ]

                Nothing ->
                    div [ class "no-note" ] [ text "No note selected" ]
            ]
        ]


viewNoteItem : Maybe NoteId -> Note -> Html Msg
viewNoteItem activeId note =
    li
        [ class "note-item"
        , classList [ ( "active", activeId == Just note.id ) ]
        , onClick (SelectNote note.id)
        ]
        [ span [ class "note-title" ] [ text (noteTitle note) ]
        , button
            [ class "delete-btn"
            , stopPropagationOn "click"
                (D.succeed ( DeleteNote note.id, True ))
            ]
            [ text "×" ]
        ]


renderContent : String -> List (Html Msg)
renderContent content =
    if String.isEmpty content then
        [ div [ class "placeholder-text" ] [ text "Click to edit..." ] ]
    else
        content
            |> String.lines
            |> List.map renderLine


renderLine : String -> Html Msg
renderLine line =
    let
        words = String.split " " line
    in
    p [] (List.intersperse (text " ") (List.map renderWord words))


renderWord : String -> Html Msg
renderWord word =
    if String.startsWith "http://" word || String.startsWith "https://" word then
        a 
            [ href word
            , target "_blank"
            , stopPropagationOn "click" (D.succeed (NoOp, True))
            ] 
            [ text word ]
    else
        text word


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


main : Program E.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
