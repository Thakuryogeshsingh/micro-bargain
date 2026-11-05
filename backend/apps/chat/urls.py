from django.urls import path

from . import views

app_name = "chat"

urlpatterns = [
    path("", views.ConversationListView.as_view(), name="list"),
    path("start/", views.StartView.as_view(), name="start"),
    path("<int:pk>/messages/", views.MessagesView.as_view(), name="messages"),
]
