FROM ubuntu:22.04 AS native-build
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gcc g++ binutils python3 libstdc++6 tzdata \
    && rm -rf /var/lib/apt/lists/*
# Exact SDK archive and SHA-256 published by the official 1.0.5 download page.
ARG CANGJIE_SDK_URL="https://cangjie-lang.cn/v1/files/auth/downLoad?nsId=142267&fileName=cangjie-sdk-linux-x64-1.0.5.tar.gz&objectKey=698acf46bd66ae22b62330b0"
ARG CANGJIE_SDK_SHA256=bacad84df8e0281c5395bab4c40e481e3ea6cc712eed5c953903b0d561a14562
RUN curl --fail --location --retry 3 "$CANGJIE_SDK_URL" -o /tmp/cangjie.tar.gz \
    && echo "$CANGJIE_SDK_SHA256  /tmp/cangjie.tar.gz" | sha256sum --check - \
    && tar -xzf /tmp/cangjie.tar.gz -C /opt && rm /tmp/cangjie.tar.gz
ENV CANGJIE_HOME=/opt/cangjie
ENV PATH=/opt/cangjie/bin:$PATH
ENV LD_LIBRARY_PATH=/opt/cangjie/runtime/lib/linux_x86_64_cjnative
WORKDIR /app
COPY work/code/*.cj work/code/
COPY work/CLI/*.cj work/CLI/
RUN cjc --version && cjc -O2 --set-runtime-rpath \
    work/code/tracker.cj work/code/working_time.cj \
    work/CLI/working_time_bridge.cj work/CLI/bridge.cj work/CLI/main.cj work/CLI/help.cj \
    -o /app/tracker-core
# Exercise the extracted native code on Linux. No proof tools or proof validation.
COPY work/code/test/runtime_test.cj work/code/test/working_time_test.cj /app/native-tests/
RUN cjc -O2 --set-runtime-rpath work/code/tracker.cj native-tests/runtime_test.cj -o /app/runtime-tests \
    && /app/runtime-tests \
    && cjc -O2 --set-runtime-rpath work/code/tracker.cj work/code/working_time.cj native-tests/working_time_test.cj -o /app/working-time-tests \
    && /app/working-time-tests

FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 ca-certificates tzdata libstdc++6 && rm -rf /var/lib/apt/lists/*
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PORT=8080 TRACKER_HOST=0.0.0.0 TRACKER_DEMO=true TRACKER_STORE_FILE=/data/shifts.store
ENV LD_LIBRARY_PATH=/opt/cangjie/runtime/lib/linux_x86_64_cjnative
WORKDIR /app
COPY --from=native-build /opt/cangjie/runtime/lib/linux_x86_64_cjnative /opt/cangjie/runtime/lib/linux_x86_64_cjnative
COPY --from=native-build /opt/cangjie/LICENSE /opt/cangjie/LICENSE
COPY --from=native-build /opt/cangjie/Open_Source_Software_Notice.docx /opt/cangjie/Open_Source_Software_Notice.docx
COPY --from=native-build /app/tracker-core /app/work/CLI/bin/tracker-core
COPY work/CLI/file_store.py work/CLI/working_time_metadata.py /app/work/CLI/
COPY work/CLI/bin/tracker /app/work/CLI/bin/tracker
COPY work/UI/*.py /app/work/UI/
COPY work/UI/static/ /app/work/UI/static/
EXPOSE 8080
CMD ["python3", "work/UI/server.py"]
