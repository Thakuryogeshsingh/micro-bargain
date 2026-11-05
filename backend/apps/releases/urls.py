from django.urls import path

from . import views

app_name = "releases"

urlpatterns = [path("latest/", views.LatestReleaseView.as_view(), name="latest")]
