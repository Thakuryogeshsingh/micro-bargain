from django.urls import path

from . import views

app_name = "support"

urlpatterns = [
    path("", views.ComplaintListCreateView.as_view(), name="list-create"),
    path("<int:pk>/", views.ComplaintDetailView.as_view(), name="detail"),
    path("<int:pk>/message/", views.ComplaintMessageView.as_view(), name="message"),
]
