# based on https://github.com/python-poetry/poetry/discussions/1879#discussioncomment-216865

# `python-base` sets up all our shared environment variables
FROM python:3.9-slim as python-base

# set our variables for python tools
ENV PYTHONUNBUFFERED=1 \
    # prevents python creating .pyc files
    PYTHONDONTWRITEBYTECODE=1 \
    \
    # pip
    PIP_NO_CACHE_DIR=off \
    PIP_DISABLE_PIP_VERSION_CHECK=on \
    PIP_DEFAULT_TIMEOUT=100 \
    \
    # poetry
    # https://python-poetry.org/docs/configuration/#using-environment-variables
    POETRY_VERSION=1.1.7 \
    # make poetry install to this location
    POETRY_HOME="/opt/poetry" \
    # make poetry create the virtual environment in the project's root
    # it gets named `.venv`
    POETRY_VIRTUALENVS_IN_PROJECT=true \
    # do not ask any interactive question
    POETRY_NO_INTERACTION=1 \
    \
    # paths
    # this is where our requirements + virtual environment will live
    PYSETUP_PATH="/opt/pysetup" \
    VENV_PATH="/opt/pysetup/.venv"

# prepend poetry and venv to path
ENV PATH="$POETRY_HOME/bin:$VENV_PATH/bin:$PATH"

# `builder-base` stage is used to build deps + create our virtual environment
FROM python-base as builder-base
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
    # deps for installing poetry
    curl \
    # deps for building python deps
    build-essential \
    # clean up
    && apt autoremove -y && apt clean

# install poetry - respects $POETRY_VERSION & $POETRY_HOME
RUN curl -sSL https://raw.githubusercontent.com/python-poetry/poetry/master/get-poetry.py | python -

# copy project requirement files here to ensure they will be cached.
WORKDIR $PYSETUP_PATH
COPY poetry.lock pyproject.toml ./

# freeze dependencies to a requirements.txt
RUN poetry export --without-hashes -f requirements.txt > requirements.txt

RUN \
    # workaround to use torch cpu 1.10.2
    sed -i 's/torch==1.10.2/torch==1.10.2+cpu/g' requirements.txt \
    && sed -i '/^torch==1.10.2.*/i -f https://download.pytorch.org/whl/torch_stable.html' requirements.txt \
    # same thing for torchvision cpu 0.11.3
    && sed -i 's/torchvision==0.11.3/torchvision==0.11.3+cpu/g' requirements.txt \
    && sed -i '/^torchvision==0.11.3.*/i -f https://download.pytorch.org/whl/cpu/torch_stable.html' requirements.txt \
    # workaround to use headless opencv
    && sed -i 's/opencv-python/opencv-python-headless/g' requirements.txt

# install runtime deps - uses $POETRY_VIRTUALENVS_IN_PROJECT internally
# RUN poetry install --no-dev
RUN poetry run pip install -r requirements.txt

# `development` image is used during development / testing
FROM python-base as development
ENV FASTAPI_ENV=development
WORKDIR $PYSETUP_PATH

# copy in our built poetry + venv
# COPY --from=builder-base $POETRY_HOME $POETRY_HOME
COPY --from=builder-base $PYSETUP_PATH $PYSETUP_PATH

# quicker install as runtime deps are already installed
# RUN poetry install
RUN pip install -r requirements.txt

# install runtime deps
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
    ffmpeg \
    # clean up
    && apt autoremove -y && apt clean

# copy stuff
COPY ./yolo_track /app/yolo_track
COPY ./deep_sort /app/deep_sort
COPY ./yolov5 /app/yolov5
COPY ./pyproject.toml /app/

# vars
ENV MODEL=/app/model

WORKDIR /app
RUN "ls"

EXPOSE 6000
ENTRYPOINT [ "python", "-m" ]