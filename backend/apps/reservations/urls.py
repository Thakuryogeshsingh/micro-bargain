from django.urls import path

from . import views

app_name = "reservations"

urlpatterns = [
    path("", views.ReservationListView.as_view(), name="list"),
    path("create/", views.ReservationCreateView.as_view(), name="create"),
    path("<int:pk>/", views.ReservationDetailView.as_view(), name="detail"),
    path("<int:pk>/confirm/", views.MerchantReservationActionView.as_view(action="confirm"), name="confirm"),
    path("<int:pk>/reject/", views.MerchantReservationActionView.as_view(action="reject"), name="reject"),
    path("<int:pk>/complete/", views.MerchantReservationActionView.as_view(action="complete"), name="complete"),
    path("<int:pk>/cancel/", views.ReservationCancelView.as_view(), name="cancel"),
]
