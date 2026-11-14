if(NOT IS_DIRECTORY "${WHISPER_SOURCE}")
    message(FATAL_ERROR "Set WHISPER_SOURCE to the local pinned whisper.cpp source directory")
endif()

find_package(Git REQUIRED)
file(STRINGS "${CMAKE_CURRENT_LIST_DIR}/WhisperSourceBlobs.txt" sourceBlobs)
set(verifiedWhisperSource "${CMAKE_CURRENT_BINARY_DIR}/verified-whisper-source")
foreach(entry IN LISTS sourceBlobs)
    if(NOT entry MATCHES "^([0-9a-f]+) (.+)$")
        message(FATAL_ERROR "Invalid source blob manifest entry: ${entry}")
    endif()
    set(expected "${CMAKE_MATCH_1}")
    set(relativePath "${CMAKE_MATCH_2}")
    set(path "${WHISPER_SOURCE}/${relativePath}")
    set(verifiedPath "${verifiedWhisperSource}/${relativePath}")
    if(NOT EXISTS "${path}" OR IS_SYMLINK "${path}" OR IS_DIRECTORY "${path}")
        message(FATAL_ERROR "Missing regular source file: ${relativePath}")
    endif()
    configure_file("${path}" "${verifiedPath}" COPYONLY)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" hash-object --no-filters -- "${verifiedPath}"
        RESULT_VARIABLE result
        OUTPUT_VARIABLE actual
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    if(NOT result EQUAL 0 OR NOT actual STREQUAL expected)
        message(FATAL_ERROR "Source file does not match the pinned whisper.cpp revision: ${relativePath}")
    endif()
endforeach()
