from django.urls import path

from . import views

app_name = "team"

urlpatterns = [
    path("", views.TeamView.as_view(), name="list"),
    path("me/", views.MyJobView.as_view(), name="me"),
    path("<int:pk>/", views.TeamMemberView.as_view(), name="member"),
]
