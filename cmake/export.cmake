install(
    TARGETS app
    DESTINATION lib/${PROJECT_NAME}
)
install(
    DIRECTORY config/
    DESTINATION share/${PROJECT_NAME}/config/
)
install(
    DIRECTORY launch/
    DESTINATION share/${PROJECT_NAME}/launch/
)

find_package(ament_cmake REQUIRED)
ament_package()
